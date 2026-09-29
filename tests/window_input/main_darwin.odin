package window_input

import ui "../../core"
import "../../core/input"
import "base:intrinsics"
import "core:fmt"
import "core:os"
import ns "core:sys/darwin/Foundation"
import cf "core:sys/darwin/CoreFoundation"

foreign import cg "system:CoreGraphics.framework"
foreign cg {
	CGEventCreateScrollWheelEvent2 :: proc(source: rawptr, units, count: u32, y, x, z: i32) -> rawptr ---
}

state: input.State
stage, attempts: int
ids: [3]ui.Identity
modal_ids: [2]ui.Identity
show_modal: bool

// AppKit windows must run on the main thread, outside Odin's test workers.
// Dispatch real NSEvents to the production view, then observe the following
// frame snapshots. No global event injection or Accessibility access is needed.
main :: proc() {
	ui.open_window("Native input check", 240, 140, check_input)
}

check_input :: proc() {
	state = ui.current_frame().input
	for i in 0..<3 {
		ui.open_rect(.Top, 40, key = i)
		ids[i] = ui.current_identity()
		ui.focusable(i != 1)
		ui.paint(color = {1, 0.5, 0, 1} if ui.focused() else {0.1, 0.2, 0.3, 1})
		ui.close_rect()
	}
	if show_modal {
		ui.open_layer(20)
		ui.open_rect_at(ui.Rect{size = {240, 140}}, key = 100)
		ui.focus_fence()
		for i in 0..<2 {
			ui.open_rect(.Top, 50, key = i)
			modal_ids[i] = ui.current_identity()
			ui.focusable()
			ui.close_rect()
		}
		ui.close_rect()
		ui.close_layer()
	}
	window := intrinsics.objc_send(^ns.Window, ns.Application.sharedApplication(), "keyWindow")
	if window == nil {
		attempts += 1
		assert(attempts < 120, "Window failed to become key")
		return
	}
	view := window->contentView()
	assert(intrinsics.objc_send(ns.id, window, "firstResponder") == cast(ns.id)view)
	switch stage {
	case 0:
		assert(state.scroll_delta == [2]f32{})
		send_scroll(view, true, -12, 7)
		send_scroll(view, true, -8, -3)
		// These were delivered after this update's input snapshot.
		assert(state.scroll_delta == [2]f32{})
	case 1:
		assert(state.scroll_delta == [2]f32{-4, 20}, "Precise wheel events must accumulate in logical points")
		send_scroll(view, false, -2, 1)
	case 2:
		assert(state.scroll_delta == [2]f32{-40, 80}, "Coarse wheel events must use logical line height")
	case 3:
		assert(state.scroll_delta == [2]f32{}, "Wheel movement must not repeat on idle frames")
		send_key(window, .KeyDown)
	case 4:
		assert(state.keys_down == input.Keys{.Tab} && state.keys_pressed == input.Keys{.Tab})
		assert(ui.direct_focus() == ids[0])
		send_key(window, .KeyDown, repeat = true)
	case 5:
		assert(state.keys_down == input.Keys{.Tab} && state.keys_pressed == input.Keys{.Tab})
		assert(ui.direct_focus() == ids[2], "Tab must skip disabled entries")
		send_key(window, .KeyUp)
	case 6:
		assert(state.keys_down == input.Keys{} && state.keys_pressed == input.Keys{} && state.keys_released == input.Keys{.Tab})
		assert(ui.direct_focus() == ids[2], "Key release must not cycle focus")
		send_key(window, .KeyDown, {.Shift})
		send_key(window, .KeyUp) // Shift released before this frame's snapshot.
	case 7:
		assert(state.modifiers == input.Modifiers{} && state.key_press_modifiers[.Tab] == input.Modifiers{.Shift})
		assert(ui.direct_focus() == ids[0], "Quick Shift-Tab must cycle backward")
		send_key(window, .KeyDown, {.Control})
		send_key(window, .KeyUp)
	case 8:
		assert(ui.direct_focus() == ids[0], "Control-Tab must not traverse focus")
		send_key(window, .KeyDown)
		send_key(window, .KeyUp)
	case 9:
		assert(ui.direct_focus() == ids[2])
		show_modal = true
	case 10: // First frame declaring the modal; focus settles at frame end.
	case 11:
		assert(ui.direct_focus() == modal_ids[0])
		send_key(window, .KeyDown)
		send_key(window, .KeyUp)
	case 12:
		assert(ui.direct_focus() == modal_ids[1])
		send_key(window, .KeyDown)
		send_key(window, .KeyUp)
	case 13:
		assert(ui.direct_focus() == modal_ids[0], "Tab must wrap inside the modal")
		send_key(window, .KeyDown, {.Shift})
		send_key(window, .KeyUp)
	case 14:
		assert(ui.direct_focus() == modal_ids[1], "Shift-Tab must wrap inside the modal")
		show_modal = false
	case 15: // First frame without the modal; restore at frame end.
	case 16:
		assert(ui.direct_focus() == ids[2], "Closing must restore the prior focus owner")
		send_key(window, .KeyDown)
		intrinsics.objc_send(nil, window, "resignKeyWindow")
		intrinsics.objc_send(nil, window, "makeKeyWindow")
	case 17:
		assert(state.keys_down == input.Keys{} && state.keys_pressed == input.Keys{} && state.keys_released == input.Keys{.Tab})
		assert(ui.direct_focus() == ids[2], "Window deactivation must cancel pending key presses")
		fmt.println("Verified native wheel and Tab input: repeat, quick Shift-Tab, disabled entries, modal wrapping/restoration and focus-loss reset")
		os.exit(0)
	}
	stage += 1
}

send_key :: proc(window: ^ns.Window, kind: ns.EventType, flags: ns.EventModifierFlags = {}, repeat: bool = false) {
	chars := ns.String.alloc()->initWithOdinString("\t")
	defer chars->release()
	event := intrinsics.objc_send(^ns.Event, ns.Event,
		"keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:",
		kind, ns.Point{}, flags, ns.TimeInterval(0),
		intrinsics.objc_send(ns.Integer, window, "windowNumber"), cast(ns.id)nil,
		chars, chars, ns.BOOL(repeat), u16(48))
	assert(event != nil)
	intrinsics.objc_send(nil, window, "sendEvent:", event)
}

send_scroll :: proc(view: ^ns.View, precise: bool, y, x: i32) {
	ref := CGEventCreateScrollWheelEvent2(nil, 0 if precise else 1, 2, y, x, 0)
	assert(ref != nil)
	defer cf.Release(cf.TypeRef(ref))
	event := intrinsics.objc_send(^ns.Event, ns.Event, "eventWithCGEvent:", ref)
	assert(event != nil)
	assert(bool(event->hasPreciseScrollingDeltas()) == precise)
	intrinsics.objc_send(nil, view, "scrollWheel:", event)
}
