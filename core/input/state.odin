// Shared input data, written by the platform before the application update.
package input

Mouse_Button :: enum u8 {
	Left,
	Right,
}

Mouse_Buttons :: bit_set[Mouse_Button; u8]

State :: struct {
	// Logical points relative to the content area's top left, with Y down.
	// May continue outside during a drag. Wayland retains the last known
	// position after pointer leave; macOS can sample global pointer position.
	mouse_position: [2]f32,
	// Pointer is known to be inside the content area. Wayland also requires
	// pointer focus, since global pointer position is not available.
	mouse_inside: bool,
	// Currently known held buttons. Both flags may be set. Wayland clears
	// the set on pointer leave or loss of the pointer device.
	// This is down-state, not a one-frame click or release event.
	mouse_buttons: Mouse_Buttons,
}
