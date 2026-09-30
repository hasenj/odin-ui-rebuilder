package platform

import "../core/input"

@(private)
Keyboard_Input :: struct {
	down, pressed, released: input.Keys,
	modifiers: input.Modifiers,
	locks: input.Locks,
	press_modifiers: [input.Key]input.Modifiers,
}

@(private)
keyboard_press :: proc(keyboard: ^Keyboard_Input, key: input.Key) {
	keyboard.down += {key}
	keyboard.pressed += {key}
	keyboard.press_modifiers[key] = keyboard.modifiers
}

@(private)
keyboard_release :: proc(keyboard: ^Keyboard_Input, key: input.Key) {
	if key in keyboard.down { keyboard.released += {key} }
	keyboard.down -= {key}
}

@(private)
keyboard_clear :: proc(keyboard: ^Keyboard_Input) {
	keyboard.released |= keyboard.down
	keyboard.down, keyboard.pressed, keyboard.modifiers, keyboard.press_modifiers = {}, {}, {}, {}
}

@(private)
sample_keyboard :: proc(keyboard: ^Keyboard_Input, state: ^input.State) {
	if state != nil {
		state.keys_down = keyboard.down
		state.keys_pressed = keyboard.pressed
		state.keys_released = keyboard.released
		state.modifiers = keyboard.modifiers
		state.locks = keyboard.locks
		state.has_key_press_modifiers = true
		state.key_press_modifiers = keyboard.press_modifiers
	}
	keyboard.pressed, keyboard.released, keyboard.press_modifiers = {}, {}, {}
}
