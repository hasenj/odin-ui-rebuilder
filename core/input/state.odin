// Shared input data, written by the platform before the application update.
package input

Mouse_Button :: enum u8 {
	Left,
	Right,
}

Mouse_Buttons :: bit_set[Mouse_Button; u8]

State :: struct {
	// Logical points relative to the content area's top left, with Y down.
	// Position continues updating outside the content area and is not clamped.
	mouse_position: [2]f32,
	// Geometric containment in the content area, not an occlusion/focus test.
	mouse_inside: bool,
	// Currently held buttons, refreshed every frame. Both flags may be set.
	// This is down-state, not a one-frame click or release event.
	mouse_buttons: Mouse_Buttons,
}
