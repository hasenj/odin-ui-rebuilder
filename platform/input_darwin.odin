package platform

import "base:intrinsics"
import ns "core:sys/darwin/Foundation"
import mtk "vendor:darwin/MetalKit"
import "../core/input"

@(private)
metal_view_scroll_wheel :: proc "c" (self: ns.id, _: ns.SEL, event: ^ns.Event) {
	delegate := intrinsics.objc_send(ns.id, cast(^mtk.View)self, "delegate")
	if delegate == nil {
		return
	}
	renderer := (cast(^^Metal_Renderer)ns.object_getIndexedIvars(delegate))^
	context = renderer.odin_context
	// AppKit has already applied the user's natural-scroll preference. Precise
	// deltas are logical points, independent of the drawable's Retina scale.
	// Traditional wheels report lines; use 40 points per line for this host.
	unit: f32 = 1 if event->hasPreciseScrollingDeltas() else 40
	renderer.pending_scroll -= [2]f32{f32(event->scrollingDeltaX()), f32(event->scrollingDeltaY())} * unit
}

@(private)
sample_frame_input :: proc(renderer: ^Metal_Renderer) {
	// Drain before calling app code: events delivered during rendering belong
	// to the next update. Held pointer state is sampled separately.
	delta := renderer.pending_scroll
	renderer.pending_scroll = {}
	sample_input(renderer.view, renderer.input_state)
	if renderer.input_state != nil {
		renderer.input_state.scroll_delta = delta
	}
	sample_keyboard(&renderer.keyboard, renderer.input_state)
}

@(private)
metal_view_renderer :: proc "contextless" (self: ns.id) -> ^Metal_Renderer {
	delegate := intrinsics.objc_send(ns.id, cast(^mtk.View)self, "delegate")
	return (cast(^^Metal_Renderer)ns.object_getIndexedIvars(delegate))^ if delegate != nil else nil
}

@(private)
macos_modifiers :: proc(flags: ns.EventModifierFlags) -> input.Modifiers {
	result: input.Modifiers
	if .Shift in flags { result += {.Shift} }
	if .Control in flags { result += {.Control} }
	if .Option in flags { result += {.Alt} }
	if .Command in flags { result += {.Super} }
	return result
}

@(private)
macos_update_flags :: proc(keyboard: ^Keyboard_Input, flags: ns.EventModifierFlags) {
	keyboard.modifiers = macos_modifiers(flags)
	keyboard.locks = {.Caps} if .CapsLock in flags else {}
}

@(private)
macos_key :: proc(code: u16) -> (key: input.Key, ok: bool) {
	switch ns.kVK(code) {
	case .Tab: return .Tab, true
	case .Return: return .Enter, true
	case .Space: return .Space, true
	case .Escape: return .Escape, true
	case .LeftArrow: return .Left, true
	case .RightArrow: return .Right, true
	case .UpArrow: return .Up, true
	case .DownArrow: return .Down, true
	case .Home: return .Home, true
	case .End: return .End, true
	case .Delete: return .Backspace, true
	case .ForwardDelete: return .Delete, true
	case .ANSI_A: return .A, true
	case .ANSI_B: return .B, true
	case .ANSI_C: return .C, true
	case .ANSI_D: return .D, true
	case .ANSI_E: return .E, true
	case .ANSI_F: return .F, true
	case .ANSI_G: return .G, true
	case .ANSI_H: return .H, true
	case .ANSI_I: return .I, true
	case .ANSI_J: return .J, true
	case .ANSI_K: return .K, true
	case .ANSI_L: return .L, true
	case .ANSI_M: return .M, true
	case .ANSI_N: return .N, true
	case .ANSI_O: return .O, true
	case .ANSI_P: return .P, true
	case .ANSI_Q: return .Q, true
	case .ANSI_R: return .R, true
	case .ANSI_S: return .S, true
	case .ANSI_T: return .T, true
	case .ANSI_U: return .U, true
	case .ANSI_V: return .V, true
	case .ANSI_W: return .W, true
	case .ANSI_X: return .X, true
	case .ANSI_Y: return .Y, true
	case .ANSI_Z: return .Z, true
	case .ANSI_0: return .Digit0, true
	case .ANSI_1: return .Digit1, true
	case .ANSI_2: return .Digit2, true
	case .ANSI_3: return .Digit3, true
	case .ANSI_4: return .Digit4, true
	case .ANSI_5: return .Digit5, true
	case .ANSI_6: return .Digit6, true
	case .ANSI_7: return .Digit7, true
	case .ANSI_8: return .Digit8, true
	case .ANSI_9: return .Digit9, true
	case .ANSI_Minus: return .Minus, true
	case .ANSI_Equal: return .Equal, true
	case .ANSI_LeftBracket: return .LeftBracket, true
	case .ANSI_RightBracket: return .RightBracket, true
	case .ANSI_Backslash: return .Backslash, true
	case .ANSI_Semicolon: return .Semicolon, true
	case .ANSI_Quote: return .Apostrophe, true
	case .ANSI_Grave: return .Grave, true
	case .ANSI_Comma: return .Comma, true
	case .ANSI_Period: return .Period, true
	case .ANSI_Slash: return .Slash, true
	case .F1: return .F1, true
	case .F2: return .F2, true
	case .F3: return .F3, true
	case .F4: return .F4, true
	case .F5: return .F5, true
	case .F6: return .F6, true
	case .F7: return .F7, true
	case .F8: return .F8, true
	case .F9: return .F9, true
	case .F10: return .F10, true
	case .F11: return .F11, true
	case .F12: return .F12, true
	case .F13: return .F13, true
	case .F14: return .F14, true
	case .F15: return .F15, true
	case .F16: return .F16, true
	case .F17: return .F17, true
	case .F18: return .F18, true
	case .F19: return .F19, true
	case .F20: return .F20, true
	case .Help: return .Insert, true
	case .PageUp: return .PageUp, true
	case .PageDown: return .PageDown, true
	case .CapsLock: return .CapsLock, true
	case .ANSI_Keypad0: return .Keypad0, true
	case .ANSI_Keypad1: return .Keypad1, true
	case .ANSI_Keypad2: return .Keypad2, true
	case .ANSI_Keypad3: return .Keypad3, true
	case .ANSI_Keypad4: return .Keypad4, true
	case .ANSI_Keypad5: return .Keypad5, true
	case .ANSI_Keypad6: return .Keypad6, true
	case .ANSI_Keypad7: return .Keypad7, true
	case .ANSI_Keypad8: return .Keypad8, true
	case .ANSI_Keypad9: return .Keypad9, true
	case .ANSI_KeypadDecimal: return .KeypadDecimal, true
	case .ANSI_KeypadDivide: return .KeypadDivide, true
	case .ANSI_KeypadMultiply: return .KeypadMultiply, true
	case .ANSI_KeypadMinus: return .KeypadSubtract, true
	case .ANSI_KeypadPlus: return .KeypadAdd, true
	case .ANSI_KeypadEnter: return .KeypadEnter, true
	case .ANSI_KeypadEquals: return .KeypadEqual, true
	case .ANSI_KeypadClear: return .KeypadClear, true
	case .Shift: return .LeftShift, true
	case .RightShift: return .RightShift, true
	case .Control: return .LeftControl, true
	case .RightControl: return .RightControl, true
	case .Option: return .LeftAlt, true
	case .RightOption: return .RightAlt, true
	case .Command: return .LeftSuper, true
	case .RightCommand: return .RightSuper, true
	case .ISO_Section: return .ISO_Backslash, true
	case .JIS_Yen: return .IntlYen, true
	case .JIS_Underscore: return .IntlRo, true
	case .JIS_KeypadComma: return .KeypadComma, true
	case .JIS_Kana: return .Kana, true
	case .JIS_Eisu: return .Eisu, true
	case .Function: return .Fn, true
	case .VolumeUp: return .VolumeUp, true
	case .VolumeDown: return .VolumeDown, true
	case .Mute: return .Mute, true
	}
	return {}, false
}

@(private)
metal_view_key_down :: proc "c" (self: ns.id, _: ns.SEL, event: ^ns.Event) {
	renderer := metal_view_renderer(self)
	if renderer == nil { return }
	context = renderer.odin_context
	macos_update_flags(&renderer.keyboard, event->modifierFlags())
	if key, ok := macos_key(event->keyCode()); ok {
		// Repeated native keyDown events also produce one-frame presses.
		keyboard_press(&renderer.keyboard, key)
	}
}

@(private)
metal_view_key_up :: proc "c" (self: ns.id, _: ns.SEL, event: ^ns.Event) {
	renderer := metal_view_renderer(self)
	if renderer == nil { return }
	context = renderer.odin_context
	macos_update_flags(&renderer.keyboard, event->modifierFlags())
	if key, ok := macos_key(event->keyCode()); ok { keyboard_release(&renderer.keyboard, key) }
}

@(private)
metal_view_flags_changed :: proc "c" (self: ns.id, _: ns.SEL, event: ^ns.Event) {
	renderer := metal_view_renderer(self)
	if renderer == nil { return }
	context = renderer.odin_context
	keyboard := &renderer.keyboard
	previous_locks := keyboard.locks
	flags := event->modifierFlags()
	macos_update_flags(keyboard, flags)
	macos_sync_modifier_keys(keyboard, flags, true)
	// AppKit reports Caps Lock changes rather than reliable physical key-up.
	// Expose a tap on each toggle, with the persistent state in input.locks.
	if keyboard.locks != previous_locks {
		keyboard_press(keyboard, .CapsLock)
		keyboard_release(keyboard, .CapsLock)
	}
}

@(private)
macos_sync_modifier_keys :: proc(keyboard: ^Keyboard_Input, flags: ns.EventModifierFlags, emit_presses: bool) {
	// Device-dependent masks from IOKit/hidsystem/IOLLEvent.h distinguish
	// releasing one Shift/Control/Option/Command while the other stays held.
	for item in ([?]struct {key: input.Key, mask: u64}{
		{.LeftControl, 0x01}, {.LeftShift, 0x02}, {.RightShift, 0x04},
		{.LeftSuper, 0x08}, {.RightSuper, 0x10}, {.LeftAlt, 0x20},
		{.RightAlt, 0x40}, {.RightControl, 0x2000}, {.Fn, 0x800000},
	}) {
		down := (transmute(u64)flags) & item.mask != 0
		if down && item.key not_in keyboard.down {
			if emit_presses { keyboard_press(keyboard, item.key) } else { keyboard.down += {item.key} }
		}
		if !down { keyboard_release(keyboard, item.key) }
	}
}

@(private)
window_became_key :: proc "c" (self: ns.id, _: ns.SEL, _: ns.id) {
	renderer := (cast(^^Metal_Renderer)ns.object_getIndexedIvars(self))^
	context = renderer.odin_context
	restore_main_window_role()
	flags := intrinsics.objc_send(ns.EventModifierFlags, ns.Event, "modifierFlags")
	macos_update_flags(&renderer.keyboard, flags)
	macos_sync_modifier_keys(&renderer.keyboard, flags, false)
}

@(private)
window_resigned_key :: proc "c" (self: ns.id, _: ns.SEL, _: ns.id) {
	renderer := (cast(^^Metal_Renderer)ns.object_getIndexedIvars(self))^
	context = renderer.odin_context
	keyboard_clear(&renderer.keyboard)
}

@(private)
sample_input :: proc(view: ^ns.View, state: ^input.State) {
	if state == nil {
		return
	}
	window := intrinsics.objc_send(^ns.Window, view, "window")
	if window == nil {
		state^ = {}
		return
	}
	// Poll current state rather than retaining the last mouse-moved event. This
	// also tracks a stationary pointer correctly when the window moves/resizes.
	point := window->convertPointFromScreen(ns.Event.mouseLocation())
	point = view->convertPointFromView(point, nil)
	bounds := view->bounds()
	x := f32(point.x - bounds.origin.x)
	y := f32(point.y - bounds.origin.y)
	if !view->isFlipped() {
		y = f32(bounds.size.height) - y
	}
	state.mouse_position = {x, y}
	// Bounds alone are insufficient when another native window overlaps ours.
	front := intrinsics.objc_send(ns.Integer, ns.Window, "windowNumberAtPoint:belowWindowWithWindowNumber:", ns.Event.mouseLocation(), ns.Integer(0))
	number := intrinsics.objc_send(ns.Integer, window, "windowNumber")
	state.mouse_inside = front == number && x >= 0 && y >= 0 && x < f32(bounds.size.width) && y < f32(bounds.size.height)

	// NSEvent's mask uses bit 0 for left and bit 1 for right. Map only the
	// supported buttons and replace the set so releases cannot leave stale flags.
	buttons := intrinsics.objc_send(ns.UInteger, ns.Event, "pressedMouseButtons")
	state.mouse_buttons = {}
	// Keep a drag alive outside the window while it owns native keyboard focus.
	if !intrinsics.objc_send(ns.BOOL, window, "isKeyWindow") { return }
	if buttons & 1 != 0 {
		state.mouse_buttons += {.Left}
	}
	if buttons & 2 != 0 {
		state.mouse_buttons += {.Right}
	}
}
