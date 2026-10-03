package window_input

import ui "../../core"
import "../../core/input"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"
import ns "core:sys/darwin/Foundation"
import cf "core:sys/darwin/CoreFoundation"
import mtk "vendor:darwin/MetalKit"

foreign import cg "system:CoreGraphics.framework"
foreign cg {
	CGEventCreateScrollWheelEvent2 :: proc(source: rawptr, units, count: u32, y, x, z: i32) -> rawptr ---
}

state: input.State
stage, attempts: int
ids: [3]ui.Identity
modal_ids: [2]ui.Identity
show_modal: bool
pump_ticks: int

// AppKit windows must run on the main thread, outside Odin's test workers.
// Dispatch real NSEvents to the production view, then observe the following
// frame snapshots. No global event injection or Accessibility access is needed.
main :: proc() {
	// Drive this test explicitly: MTKView's display timer can stop entirely when
	// the display sleeps or the window is occluded. Input tests must still finish.
	cls := ns.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "InputTestFramePump", 0)
	assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("tick:"), auto_cast pump_frame, "v@:@"))
	ns.objc_registerClassPair(cls)
	target := ns.class_createInstance(cls, 0)
	_ = ns.Timer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeat(1.0 / 60, target,
		intrinsics.objc_find_selector("tick:"), nil, true)
	ui.open_window("Native input check", 240, 140, check_input)
}

pump_frame :: proc "c" (_: ns.id, _: ns.SEL, _: ns.id) {
	context = runtime.default_context()
	pump_ticks += 1
	if pump_ticks > 600 { fmt.eprintln("Native input test timed out"); os.exit(1) }
	app := ns.Application.sharedApplication()
	windows := intrinsics.objc_send(^ns.Array, app, "windows")
	if intrinsics.objc_send(ns.UInteger, windows, "count") == 0 { return }
	window := intrinsics.objc_send(^ns.Window, windows, "objectAtIndex:", ns.UInteger(0))
	if !intrinsics.objc_send(ns.BOOL, window, "isKeyWindow") { intrinsics.objc_send(nil, window, "makeKeyWindow") }
	view := cast(^mtk.View)window->contentView()
	view->draw()
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
		for item in key_cases { send_key(window, .KeyDown, item.flags, code = item.code, characters = item.characters) }
	case 18:
		expected: input.Keys
		for item in key_cases {
			expected += {item.key}
			assert(state.key_press_modifiers[item.key] == (input.Modifiers{.Shift} if .Shift in item.flags else input.Modifiers{}))
		}
		assert(state.keys_down == expected && state.keys_pressed == expected)
		assert(ui.direct_focus() == ids[2], "Ordinary keys must not perform focus traversal")
		send_key(window, .KeyDown, repeat = true, code = 0, characters = "q")
	case 19:
		assert(state.keys_pressed == input.Keys{.A}, "Repeat preserves physical identity")
		for item in key_cases { send_key(window, .KeyUp, code = item.code, characters = item.characters) }
	case 20:
		expected: input.Keys
		for item in key_cases { expected += {item.key} }
		assert(state.keys_down == input.Keys{} && state.keys_pressed == input.Keys{} && state.keys_released == expected)
		send_key(window, .FlagsChanged, transmute(ns.EventModifierFlags)u64(0x20002), code = 56)
		send_key(window, .FlagsChanged, transmute(ns.EventModifierFlags)u64(0x20006), code = 60)
	case 21:
		assert(state.keys_down == input.Keys{.LeftShift, .RightShift} && state.keys_pressed == input.Keys{.LeftShift, .RightShift})
		send_key(window, .FlagsChanged, transmute(ns.EventModifierFlags)u64(0x20004), code = 56)
	case 22:
		assert(state.keys_down == input.Keys{.RightShift} && state.keys_released == input.Keys{.LeftShift} && state.modifiers == input.Modifiers{.Shift})
		send_key(window, .FlagsChanged, code = 60)
	case 23:
		assert(state.keys_down == input.Keys{} && state.keys_released == input.Keys{.RightShift} && state.modifiers == input.Modifiers{})
		send_key(window, .FlagsChanged, {.CapsLock}, code = 57)
	case 24:
		assert(state.locks == input.Locks{.Caps} && state.keys_pressed == input.Keys{.CapsLock} && state.keys_released == input.Keys{.CapsLock})
		assert(state.keys_down == input.Keys{}, "Caps Lock toggle must not leave a stuck key")
		send_key(window, .FlagsChanged, code = 57)
	case 25:
		assert(state.locks == input.Locks{} && state.keys_pressed == input.Keys{.CapsLock})
	case 26:
		assert(state.keys_pressed == input.Keys{} && state.keys_released == input.Keys{} && state.keys_down == input.Keys{})
		send_mouse(window, .LeftMouseDown)
		send_mouse(window, .LeftMouseUp)
		send_mouse(window, .RightMouseDown)
	case 27:
		assert(state.mouse_pressed == input.Mouse_Buttons{.Left, .Right})
		assert(state.mouse_released == input.Mouse_Buttons{.Left} && state.mouse_buttons == input.Mouse_Buttons{.Right})
	case 28:
		assert(state.mouse_pressed == input.Mouse_Buttons{} && state.mouse_released == input.Mouse_Buttons{})
		assert(state.mouse_buttons == input.Mouse_Buttons{.Right})
		send_mouse(window, .RightMouseUp, {-20, -20})
	case 29:
		assert(state.mouse_buttons == input.Mouse_Buttons{} && state.mouse_released == input.Mouse_Buttons{.Right})
		send_mouse(window, .LeftMouseDown)
		intrinsics.objc_send(nil, window, "resignKeyWindow")
		intrinsics.objc_send(nil, window, "makeKeyWindow")
	case 30:
		assert(state.mouse_cancelled && state.mouse_pressed == input.Mouse_Buttons{})
		assert(state.mouse_buttons == input.Mouse_Buttons{} && state.mouse_released == input.Mouse_Buttons{.Left})
	case 31:
		assert(!state.mouse_cancelled && state.mouse_released == input.Mouse_Buttons{})
		fmt.println("Verified native keyboard, quick mouse taps, holds, outside release and focus-loss cancellation")
		os.exit(0)
	}
	stage += 1
}

key_cases := [?]struct {code: u16, key: input.Key, flags: ns.EventModifierFlags, characters: string}{
	{0, .A, {}, "q"}, // Deliberately different character: key identity is physical.
	{18, .Digit1, {.Shift}, "!"}, {41, .Semicolon, {.Shift}, ":"},
	{96, .F5, {}, ""}, {82, .Keypad0, {}, "0"}, {76, .KeypadEnter, {}, "\r"},
	{36, .Enter, {}, "\r"}, {116, .PageUp, {}, ""}, {10, .ISO_Backslash, {}, "<"},
	{74, .Mute, {}, ""}, // Highest bit of the 128-key set.
}

send_key :: proc(window: ^ns.Window, kind: ns.EventType, flags: ns.EventModifierFlags = {}, repeat: bool = false, code: u16 = 48, characters: string = "\t") {
	chars := ns.String.alloc()->initWithOdinString(characters)
	defer chars->release()
	event := intrinsics.objc_send(^ns.Event, ns.Event,
		"keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:",
		kind, ns.Point{}, flags, ns.TimeInterval(0),
		intrinsics.objc_send(ns.Integer, window, "windowNumber"), cast(ns.id)nil,
		chars, chars, ns.BOOL(repeat), code)
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


send_mouse :: proc(window: ^ns.Window, kind: ns.EventType, point: ns.Point = {20, 20}) {
	event := intrinsics.objc_send(^ns.Event, ns.Event,
		"mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:",
		kind, point, ns.EventModifierFlags{}, f64(0), intrinsics.objc_send(ns.Integer, window, "windowNumber"),
		rawptr(nil), ns.Integer(0), ns.Integer(1), f32(1))
	intrinsics.objc_send(nil, window, "sendEvent:", event)
}
