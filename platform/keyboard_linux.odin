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
	xkb_state_key_get_one_sym :: proc(state: rawptr, code: u32) -> u32 ---
	xkb_keymap_key_repeats :: proc(keymap: rawptr, code: u32) -> i32 ---
}

@(private)
wayland_key :: proc(w: ^Wayland_Window, code: u32) -> (key: input.Key, ok: bool) {
	if w.xkb_state == nil { return {}, false }
	// wl_keyboard uses evdev codes; XKB keycodes are offset by 8.
	switch xkb_state_key_get_one_sym(w.xkb_state, code + 8) {
	case 0xff09, 0xfe20: return .Tab, true // Tab / ISO_Left_Tab.
	case 0xff0d, 0xff8d: return .Enter, true
	case 0x20: return .Space, true
	case 0xff1b: return .Escape, true
	case 0xff51: return .Left, true
	case 0xff53: return .Right, true
	case 0xff52: return .Up, true
	case 0xff54: return .Down, true
	case 0xff50: return .Home, true
	case 0xff57: return .End, true
	case 0xff08: return .Backspace, true
	case 0xffff: return .Delete, true
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
keyboard_leave :: proc "c" (data, _: rawptr, _: u32, _: rawptr) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	clear_wayland_keyboard(w)
}

@(private)
keyboard_key :: proc "c" (data, _: rawptr, _: u32, _: u32, code, state: u32) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	if !w.keyboard_focused { return }
	if state == 1 {
		// A newly pressed repeating key replaces the previous repeat owner,
		// even when it is a character outside our current navigation-key API.
		if w.xkb_keymap != nil && xkb_keymap_key_repeats(w.xkb_keymap, code + 8) != 0 { w.repeat_active = false }
		if key, ok := wayland_key(w, code); ok {
			w.held_keys[code] = key
			keyboard_press(&w.keyboard, key)
			if xkb_keymap_key_repeats(w.xkb_keymap, code + 8) != 0 {
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
		// Skip missed repeats rather than flooding the next frame after a stall.
		w.repeat_at = time.tick_add(time.tick_now(), max(time.Second / time.Duration(w.repeat_rate), time.Millisecond))
	}
}

@(private)
clear_wayland_keyboard :: proc(w: ^Wayland_Window) {
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
