#+build linux
package platform

import "core:testing"
import "core:time"
import "../core/input"

// Exercise the negotiated wl_pointer v5 callback pipeline without a compositor.
@(test)
wayland_wheel_snapshots :: proc(t: ^testing.T) {
	w := Wayland_Window{odin_context = context, pointer_focused = true}
	pointer_axis(&w, nil, 0, 0, 20 * 256)
	pointer_axis(&w, nil, 0, 1, -4 * 256)
	pointer_axis_discrete(&w, nil, 0, 1)
	testing.expect(t, w.input.scroll_delta == [2]f32{})
	pointer_frame(&w, nil)
	pointer_axis(&w, nil, 0, 0, 128)
	pointer_frame(&w, nil)
	snapshot := take_wayland_input(&w)
	testing.expect(t, snapshot.scroll_delta == [2]f32{-4, 20.5})
	testing.expect(t, take_wayland_input(&w).scroll_delta == [2]f32{})
	pointer_axis(&w, nil, 0, 0, 256)
	pointer_leave(&w, nil, 0, nil)
	pointer_frame(&w, nil)
	pointer_axis(&w, nil, 0, 0, 256)
	pointer_frame(&w, nil)
	testing.expect(t, take_wayland_input(&w).scroll_delta == [2]f32{}, "Pointer leave must clear and reject pending scroll")
}

// Real XKB modifiers and physical evdev keys through production callbacks.
@(test)
wayland_keyboard_snapshots :: proc(t: ^testing.T) {
	w := Wayland_Window{odin_context = context}
	w.xkb_context = xkb_context_new(0)
	assert(w.xkb_context != nil)
	w.xkb_keymap = xkb_keymap_new_from_names(w.xkb_context, nil, 0)
	assert(w.xkb_keymap != nil)
	w.xkb_state = xkb_state_new(w.xkb_keymap)
	assert(w.xkb_state != nil)
	defer destroy_wayland_keyboard(&w)
	keyboard_enter(&w, nil, 0, nil, nil)
	shift := xkb_keymap_mod_get_index(w.xkb_keymap, "Shift")
	assert(shift < 32)
	keyboard_modifiers(&w, nil, 0, u32(1) << shift, 0, 0, 0)
	keyboard_key(&w, nil, 0, 0, 15, 1)
	keyboard_key(&w, nil, 0, 0, 15, 0)
	keyboard_modifiers(&w, nil, 0, 0, 0, 0, 0)
	snapshot := take_wayland_input(&w)
	testing.expect(t, snapshot.keys_pressed == input.Keys{.Tab} && snapshot.keys_released == input.Keys{.Tab})
	testing.expect(t, snapshot.keys_down == input.Keys{} && snapshot.modifiers == input.Modifiers{})
	testing.expect(t, snapshot.has_key_press_modifiers && snapshot.key_press_modifiers[.Tab] == input.Modifiers{.Shift})
	testing.expect(t, take_wayland_input(&w).keys_pressed == input.Keys{})
	keyboard_repeat_info(&w, nil, 20, 500)
	keyboard_key(&w, nil, 0, 0, 15, 1)
	_ = take_wayland_input(&w)
	w.repeat_at = time.tick_add(time.tick_now(), -time.Millisecond)
	testing.expect(t, take_wayland_input(&w).keys_pressed == input.Keys{.Tab})
	keyboard_leave(&w, nil, 0, nil)
	snapshot = take_wayland_input(&w)
	testing.expect(t, snapshot.keys_down == input.Keys{} && snapshot.keys_pressed == input.Keys{} && snapshot.keys_released == input.Keys{.Tab})
	testing.expect(t, !w.repeat_active)
	keyboard_enter(&w, nil, 0, nil, nil)
	keyboard_modifiers(&w, nil, 0, u32(1) << shift, 0, 0, 0)
	for code in ([?]u32{30, 2, 79, 183, 113}) { keyboard_key(&w, nil, 0, 0, code, 1) }
	snapshot = take_wayland_input(&w)
	expected := input.Keys{.A, .Digit1, .Keypad1, .F13, .Mute}
	testing.expect(t, snapshot.keys_down == expected && snapshot.keys_pressed == expected)
	testing.expect(t, snapshot.key_press_modifiers[.Digit1] == input.Modifiers{.Shift})
	// Num Lock must not change keypad identity or which held key gets released.
	num := xkb_keymap_mod_get_index(w.xkb_keymap, "Mod2")
	assert(num < 32)
	keyboard_modifiers(&w, nil, 0, 0, 0, u32(1) << num, 0)
	for code in ([?]u32{30, 2, 79, 183, 113}) { keyboard_key(&w, nil, 0, 0, code, 0) }
	snapshot = take_wayland_input(&w)
	testing.expect(t, snapshot.keys_down == input.Keys{} && snapshot.keys_released == expected)
}

// Events within one update retain both transitions; leave/device loss cancels
// drags. Events for another surface on the shared connection stay isolated.
@(test)
wayland_mouse_transitions :: proc(t: ^testing.T) {
	w := Wayland_Window{odin_context = context, pointer_focused = true}
	pointer_button(&w, nil, 1, 0, 0x110, 1)
	pointer_button(&w, nil, 2, 0, 0x110, 0)
	snapshot := take_wayland_input(&w)
	testing.expect(t, snapshot.mouse_buttons == input.Mouse_Buttons{})
	testing.expect(t, snapshot.mouse_pressed == input.Mouse_Buttons{.Left} && snapshot.mouse_released == input.Mouse_Buttons{.Left})
	snapshot = take_wayland_input(&w)
	testing.expect(t, snapshot.mouse_pressed == input.Mouse_Buttons{} && snapshot.mouse_released == input.Mouse_Buttons{})
	pointer_button(&w, nil, 3, 0, 0x111, 1)
	pointer_leave(&w, nil, 4, nil)
	snapshot = take_wayland_input(&w)
	testing.expect(t, snapshot.mouse_cancelled && snapshot.mouse_buttons == input.Mouse_Buttons{} && .Right in snapshot.mouse_released)
	pointer_button(&w, nil, 5, 0, 0x110, 1)
	testing.expect(t, take_wayland_input(&w).mouse_buttons == input.Mouse_Buttons{})
	w.surface = rawptr(uintptr(1))
	w.pointer_focused = true
	pointer_button(&w, nil, 6, 0, 0x110, 1)
	pointer_leave(&w, nil, 7, rawptr(uintptr(2)))
	testing.expect(t, w.pointer_focused && .Left in take_wayland_input(&w).mouse_buttons)
}
