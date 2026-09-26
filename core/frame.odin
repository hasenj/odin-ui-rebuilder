package ui

import "primitives"

Rectangle :: primitives.Rectangle
Color :: primitives.Color

// The framework clears rectangles before each update, retaining its capacity.
// Append this frame's primitives; do not retain the slice across updates.
Frame :: struct {
	time:       f64, // Monotonic seconds since the window opened.
	size:       [2]f32, // Current content size in logical points.
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
