package ui

import "primitives"
import "input"

Rectangle :: primitives.Rectangle
Color :: primitives.Color
Input :: input.State
Mouse_Button :: input.Mouse_Button
Mouse_Buttons :: input.Mouse_Buttons

// The framework clears rectangles before each update, retaining its capacity.
// Append this frame's primitives; do not retain the slice across updates.
Frame :: struct {
	time:       f64, // Monotonic seconds since the window opened.
	size:       [2]f32, // Current content size in logical points.
	input:      Input, // Current input snapshot; read this during update.
	rectangles: [dynamic]Rectangle,
}

Update :: #type proc(frame: ^Frame)

@(private)
Frame_State :: struct {
	frame:  Frame,
	update: Update,
}

@(private)
build_frame :: proc(elapsed: f64, size: [2]f32, user_data: rawptr) -> []Rectangle {
	state := cast(^Frame_State)user_data
	state.frame.time = elapsed
	state.frame.size = size
	clear(&state.frame.rectangles)
	if state.update != nil {
		state.update(&state.frame)
	}
	return state.frame.rectangles[:]
}
