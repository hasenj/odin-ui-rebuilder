// Shared input data, written by the platform before the application update.
package input

Mouse_Button :: enum u8 {
	Left,
	Right,
}

Mouse_Buttons :: bit_set[Mouse_Button; u8]

// Physical key positions, named using US keyboard legends. Shift/layout do not
// change a key's identity. Text/IME will have a separate data contract.
Key :: enum u8 {
	Tab, Enter, Space, Escape, Left, Right, Up, Down, Home, End, Backspace, Delete,
	A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
	Digit0, Digit1, Digit2, Digit3, Digit4, Digit5, Digit6, Digit7, Digit8, Digit9,
	Minus, Equal, LeftBracket, RightBracket, Backslash, Semicolon, Apostrophe, Grave, Comma, Period, Slash,
	F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
	F13, F14, F15, F16, F17, F18, F19, F20, F21, F22, F23, F24,
	Insert, PageUp, PageDown, PrintScreen, ScrollLock, Pause, CapsLock, NumLock, Menu,
	Keypad0, Keypad1, Keypad2, Keypad3, Keypad4, Keypad5, Keypad6, Keypad7, Keypad8, Keypad9,
	KeypadDecimal, KeypadDivide, KeypadMultiply, KeypadSubtract, KeypadAdd, KeypadEnter, KeypadEqual, KeypadComma, KeypadClear,
	LeftShift, RightShift, LeftControl, RightControl, LeftAlt, RightAlt, LeftSuper, RightSuper,
	ISO_Backslash, IntlYen, IntlRo, Kana, Eisu, Fn,
	VolumeUp, VolumeDown, Mute,
}
Keys :: bit_set[Key; u128]
Modifier :: enum u8 {Shift, Control, Alt, Super}
Modifiers :: bit_set[Modifier; u8]
Lock :: enum u8 {Caps, Num, Scroll}
Locks :: bit_set[Lock; u8]

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
	// macOS accumulates mouse and keyboard transitions between updates. Both
	// pressed and released may be set for a quick tap; counts/order coalesce.
	// Hosts without native mouse accumulation can still supply held state.
	mouse_pressed, mouse_released: Mouse_Buttons,
	mouse_cancelled: bool, // Focus/device loss: end drags without activating clicks.
	keys_down, keys_pressed, keys_released: Keys,
	modifiers: Modifiers,
	locks: Locks, // Toggle state; independent of a lock key being held.
	// Native transitions remember modifiers at press time, even if Shift is
	// released before the next frame. Synthetic hosts may leave this false
	// and use modifiers for all presses, as before.
	has_key_press_modifiers: bool,
	key_press_modifiers: [Key]Modifiers,
	text: Text_Input,
}
