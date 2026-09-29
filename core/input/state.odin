// Shared input data, written by the platform before the application update.
package input

Mouse_Button :: enum u8 {
	Left,
	Right,
}

Mouse_Buttons :: bit_set[Mouse_Button; u8]

Key :: enum u8 {Tab, Enter, Space, Escape, Left, Right, Up, Down, Home, End, Backspace, Delete}
Keys :: bit_set[Key; u64]
Modifier :: enum u8 {Shift, Control, Alt, Super}
Modifiers :: bit_set[Modifier; u8]

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
	// Per-update wheel/trackpad delta in logical points. Positive moves the
	// viewport towards the content bottom/right. Native hosts accumulate events
	// between frames, then clear their pending delta after supplying the snapshot.
	scroll_delta: [2]f32,
	// Transition sets are supplied per update; they are not retained/consumed.
	// These fields are currently for synthetic hosts; native keyboard wiring is pending.
	mouse_pressed, mouse_released: Mouse_Buttons,
	keys_down, keys_pressed, keys_released: Keys,
	modifiers: Modifiers,
}
