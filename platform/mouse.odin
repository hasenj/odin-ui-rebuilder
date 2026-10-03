package platform

import "../core/input"

@(private) Mouse_Input :: struct {
	down, pressed, released: input.Mouse_Buttons,
	cancelled: bool,
}

@(private) mouse_press :: proc(mouse: ^Mouse_Input, button: input.Mouse_Button) {
	mouse.down += {button}
	mouse.pressed += {button}
}
@(private) mouse_release :: proc(mouse: ^Mouse_Input, button: input.Mouse_Button) {
	if button in mouse.down { mouse.released += {button} }
	mouse.down -= {button}
}
@(private) mouse_clear :: proc(mouse: ^Mouse_Input) {
	mouse.released |= mouse.down
	mouse.down, mouse.pressed = {}, {}
	mouse.cancelled = true
}
@(private) sample_mouse :: proc(mouse: ^Mouse_Input, state: ^input.State) {
	if state != nil {
		state.mouse_buttons = mouse.down
		state.mouse_pressed, state.mouse_released = mouse.pressed, mouse.released
		state.mouse_cancelled = mouse.cancelled
	}
	mouse.pressed, mouse.released, mouse.cancelled = {}, {}, false
}
