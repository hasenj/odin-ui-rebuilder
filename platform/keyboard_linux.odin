package platform

import "core:sys/posix"
import "core:time"
import "../core/input"

// The compositor's keymap defines layout and modifier indices. Do not assume
// that Shift/Control/Alt/Super use fixed bits in wl_keyboard.modifiers.
foreign import xkb "system:xkbcommon"
foreign xkb {
	xkb_context_new :: proc(flags: u32) -> rawptr ---
	xkb_context_unref :: proc(ctx: rawptr) ---
	xkb_keymap_new_from_string :: proc(ctx: rawptr, source: cstring, format, flags: u32) -> rawptr ---
	xkb_keymap_new_from_names :: proc(ctx, names: rawptr, flags: u32) -> rawptr ---
	xkb_keymap_mod_get_index :: proc(keymap: rawptr, name: cstring) -> u32 ---
	xkb_keymap_unref :: proc(keymap: rawptr) ---
	xkb_state_new :: proc(keymap: rawptr) -> rawptr ---
	xkb_state_unref :: proc(state: rawptr) ---
	xkb_state_update_mask :: proc(state: rawptr, depressed, latched, locked, depressed_layout, latched_layout, locked_layout: u32) -> u32 ---
	xkb_state_mod_name_is_active :: proc(state: rawptr, name: cstring, component: u32) -> i32 ---
	xkb_state_led_name_is_active :: proc(state: rawptr, name: cstring) -> i32 ---
	xkb_keymap_key_repeats :: proc(keymap: rawptr, code: u32) -> i32 ---
}

@(private)
wayland_key :: proc(_: ^Wayland_Window, code: u32) -> (key: input.Key, ok: bool) {
	// Physical evdev positions; independent of layout, Shift and Num Lock.
	switch code {
	case 1: return .Escape, true
	case 2: return .Digit1, true
	case 3: return .Digit2, true
	case 4: return .Digit3, true
	case 5: return .Digit4, true
	case 6: return .Digit5, true
	case 7: return .Digit6, true
	case 8: return .Digit7, true
	case 9: return .Digit8, true
	case 10: return .Digit9, true
	case 11: return .Digit0, true
	case 12: return .Minus, true
	case 13: return .Equal, true
	case 14: return .Backspace, true
	case 15: return .Tab, true
	case 16: return .Q, true
	case 17: return .W, true
	case 18: return .E, true
	case 19: return .R, true
	case 20: return .T, true
	case 21: return .Y, true
	case 22: return .U, true
	case 23: return .I, true
	case 24: return .O, true
	case 25: return .P, true
	case 26: return .LeftBracket, true
	case 27: return .RightBracket, true
	case 28: return .Enter, true
	case 29: return .LeftControl, true
	case 30: return .A, true
	case 31: return .S, true
	case 32: return .D, true
	case 33: return .F, true
	case 34: return .G, true
	case 35: return .H, true
	case 36: return .J, true
	case 37: return .K, true
	case 38: return .L, true
	case 39: return .Semicolon, true
	case 40: return .Apostrophe, true
	case 41: return .Grave, true
	case 42: return .LeftShift, true
	case 43: return .Backslash, true
	case 44: return .Z, true
	case 45: return .X, true
	case 46: return .C, true
	case 47: return .V, true
	case 48: return .B, true
	case 49: return .N, true
	case 50: return .M, true
	case 51: return .Comma, true
	case 52: return .Period, true
	case 53: return .Slash, true
	case 54: return .RightShift, true
	case 55: return .KeypadMultiply, true
	case 56: return .LeftAlt, true
	case 57: return .Space, true
	case 58: return .CapsLock, true
	case 59: return .F1, true
	case 60: return .F2, true
	case 61: return .F3, true
	case 62: return .F4, true
	case 63: return .F5, true
	case 64: return .F6, true
	case 65: return .F7, true
	case 66: return .F8, true
	case 67: return .F9, true
	case 68: return .F10, true
	case 69: return .NumLock, true
	case 70: return .ScrollLock, true
	case 71: return .Keypad7, true
	case 72: return .Keypad8, true
	case 73: return .Keypad9, true
	case 74: return .KeypadSubtract, true
	case 75: return .Keypad4, true
	case 76: return .Keypad5, true
	case 77: return .Keypad6, true
	case 78: return .KeypadAdd, true
	case 79: return .Keypad1, true
	case 80: return .Keypad2, true
	case 81: return .Keypad3, true
	case 82: return .Keypad0, true
	case 83: return .KeypadDecimal, true
	case 86: return .ISO_Backslash, true
	case 87: return .F11, true
	case 88: return .F12, true
	case 89: return .IntlRo, true
	case 95: return .KeypadComma, true
	case 96: return .KeypadEnter, true
	case 97: return .RightControl, true
	case 98: return .KeypadDivide, true
	case 99: return .PrintScreen, true
	case 100: return .RightAlt, true
	case 102: return .Home, true
	case 103: return .Up, true
	case 104: return .PageUp, true
	case 105: return .Left, true
	case 106: return .Right, true
	case 107: return .End, true
	case 108: return .Down, true
	case 109: return .PageDown, true
	case 110: return .Insert, true
	case 111: return .Delete, true
	case 113: return .Mute, true
	case 114: return .VolumeDown, true
	case 115: return .VolumeUp, true
	case 117: return .KeypadEqual, true
	case 119: return .Pause, true
	case 121: return .KeypadComma, true
	case 122: return .Kana, true // HID LANG1, including JIS Kana.
	case 123: return .Eisu, true // HID LANG2, including JIS Eisu.
	case 124: return .IntlYen, true
	case 125: return .LeftSuper, true
	case 126: return .RightSuper, true
	case 127: return .Menu, true
	case 139: return .Menu, true
	case 183: return .F13, true
	case 184: return .F14, true
	case 185: return .F15, true
	case 186: return .F16, true
	case 187: return .F17, true
	case 188: return .F18, true
	case 189: return .F19, true
	case 190: return .F20, true
	case 191: return .F21, true
	case 192: return .F22, true
	case 193: return .F23, true
	case 194: return .F24, true
	case 355: return .KeypadClear, true
	case 464: return .Fn, true
	}
	return {}, false
}

@(private)
keyboard_keymap :: proc "c" (data, _: rawptr, format: u32, fd: i32, size: u32) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	defer posix.close(posix.FD(fd))
	if format != 1 || size == 0 { return }
	bytes := posix.mmap(nil, uint(size), {.READ}, {.PRIVATE}, posix.FD(fd))
	if bytes == posix.MAP_FAILED { return }
	defer posix.munmap(bytes, uint(size))
	if (cast([^]byte)bytes)[size - 1] != 0 { return }
	if w.xkb_context == nil { w.xkb_context = xkb_context_new(0) }
	if w.xkb_context == nil { return }
	keymap := xkb_keymap_new_from_string(w.xkb_context, cast(cstring)bytes, 1, 0)
	if keymap == nil { return }
	state := xkb_state_new(keymap)
	if state == nil { xkb_keymap_unref(keymap); return }
	keyboard_clear(&w.keyboard)
	clear(&w.held_keys)
	w.repeat_active = false
	if w.xkb_state != nil { xkb_state_unref(w.xkb_state) }
	if w.xkb_keymap != nil { xkb_keymap_unref(w.xkb_keymap) }
	w.xkb_keymap, w.xkb_state = keymap, state
}

@(private)
keyboard_enter :: proc "c" (data, _: rawptr, _: u32, surface: rawptr, keys: ^WL_Array) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	if surface != w.surface { return }
	clear_wayland_keyboard(w)
	w.keyboard_focused = true
	if w.held_keys == nil { w.held_keys = make(map[u32]input.Key) }
	if keys != nil {
		for code in (cast([^]u32)keys.data)[:int(keys.size / size_of(u32))] {
			if key, ok := wayland_key(w, code); ok {
				w.held_keys[code] = key
				w.keyboard.down += {key} // Enter is held state, not a new press.
			}
		}
	}
}

@(private)
keyboard_leave :: proc "c" (data, _: rawptr, _: u32, surface: rawptr) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	if surface != w.surface { return }
	clear_wayland_keyboard(w)
	mouse_clear(&w.mouse)
}

@(private)
keyboard_key :: proc "c" (data, _: rawptr, serial: u32, _: u32, code, state: u32) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	if !w.keyboard_focused { return }
	w.clipboard.serial = serial
	if state == 1 {
		wayland_text_key(w, code)
		// A newly pressed repeating key replaces the previous repeat owner,
		// even when its code is outside the named-key API.
		repeats := w.xkb_keymap != nil && xkb_keymap_key_repeats(w.xkb_keymap, code + 8) != 0
		if repeats { w.repeat_active = false }
		if key, ok := wayland_key(w, code); ok {
			w.held_keys[code] = key
			keyboard_press(&w.keyboard, key)
			if repeats {
				w.repeat_active, w.repeat_code = w.repeat_rate > 0, code
				w.repeat_at = time.tick_add(time.tick_now(), time.Duration(w.repeat_delay) * time.Millisecond)
			}
		}
	} else if key, ok := w.held_keys[code]; ok {
		delete_key(&w.held_keys, code)
		still_down := false
		for _, held in w.held_keys { if held == key { still_down = true; break } }
		if !still_down { keyboard_release(&w.keyboard, key) }
		if w.repeat_code == code { w.repeat_active = false }
	}
}

@(private)
keyboard_modifiers :: proc "c" (data, _: rawptr, _: u32, depressed, latched, locked, group: u32) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	if w.xkb_state == nil || !w.keyboard_focused { return }
	xkb_state_update_mask(w.xkb_state, depressed, latched, locked, 0, 0, group)
	w.keyboard.modifiers = {}
	w.keyboard.locks = {}
	if xkb_state_led_name_is_active(w.xkb_state, "Caps Lock") > 0 { w.keyboard.locks += {.Caps} }
	if xkb_state_led_name_is_active(w.xkb_state, "Num Lock") > 0 { w.keyboard.locks += {.Num} }
	if xkb_state_led_name_is_active(w.xkb_state, "Scroll Lock") > 0 { w.keyboard.locks += {.Scroll} }
	// XKB_STATE_MODS_EFFECTIVE = 1 << 3, including latched/locked modifiers.
	if xkb_state_mod_name_is_active(w.xkb_state, "Shift", 8) > 0 { w.keyboard.modifiers += {.Shift} }
	if xkb_state_mod_name_is_active(w.xkb_state, "Control", 8) > 0 { w.keyboard.modifiers += {.Control} }
	if xkb_state_mod_name_is_active(w.xkb_state, "Mod1", 8) > 0 { w.keyboard.modifiers += {.Alt} }
	if xkb_state_mod_name_is_active(w.xkb_state, "Mod4", 8) > 0 { w.keyboard.modifiers += {.Super} }
}

@(private)
keyboard_repeat_info :: proc "c" (data, _: rawptr, rate, delay: i32) {
	w := cast(^Wayland_Window)data
	w.repeat_rate, w.repeat_delay = max(rate, 0), max(delay, 0)
	if rate <= 0 { w.repeat_active = false }
}

@(private)
wayland_repeat :: proc(w: ^Wayland_Window) {
	if !w.repeat_active || !w.keyboard_focused || w.repeat_rate <= 0 || time.tick_since(w.repeat_at) < 0 { return }
	if key, ok := w.held_keys[w.repeat_code]; ok {
		keyboard_press(&w.keyboard, key)
		wayland_text_key(w, w.repeat_code)
		// Skip missed repeats rather than flooding the next frame after a stall.
		w.repeat_at = time.tick_add(time.tick_now(), max(time.Second / time.Duration(w.repeat_rate), time.Millisecond))
	}
}

@(private)
clear_wayland_keyboard :: proc(w: ^Wayland_Window) {
	wayland_text_cancel(w)
	keyboard_clear(&w.keyboard)
	clear(&w.held_keys)
	w.keyboard_focused, w.repeat_active = false, false
}

@(private)
destroy_wayland_keyboard :: proc(w: ^Wayland_Window) {
	delete(w.held_keys)
	if w.xkb_state != nil { xkb_state_unref(w.xkb_state) }
	if w.xkb_keymap != nil { xkb_keymap_unref(w.xkb_keymap) }
	if w.xkb_context != nil { xkb_context_unref(w.xkb_context) }
}

keyboard_listener := struct {
	keymap: type_of(keyboard_keymap), enter: type_of(keyboard_enter), leave: type_of(keyboard_leave),
	key: type_of(keyboard_key), modifiers: type_of(keyboard_modifiers), repeat_info: type_of(keyboard_repeat_info),
}{keyboard_keymap, keyboard_enter, keyboard_leave, keyboard_key, keyboard_modifiers, keyboard_repeat_info}
