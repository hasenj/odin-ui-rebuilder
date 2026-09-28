package ui

import "primitives"
import "input"
import fonts "text"
import "../platform"

Surface :: primitives.Surface
Color :: primitives.Color
Input :: input.State
Mouse_Button :: input.Mouse_Button
Mouse_Buttons :: input.Mouse_Buttons

// The framework clears surfaces before each update, retaining its capacity.
// Append low-level primitives here; do not retain the slice across updates.
Frame :: struct {
	time:       f64, // Monotonic seconds since the window opened.
	size:       [2]f32, // Current content size in logical points.
	scale:      f32, // Physical pixels per logical point.
	input:      Input, // Current input snapshot; read this during update.
	renderer:   platform.Renderer, // Used by image loading; owned by the window.
	surfaces:   [dynamic]Surface,
}

Update :: #type proc()

// Valid during update and helpers called from it, on the window's main thread.
current_frame :: proc() -> ^Frame {
	assert(active_state != nil, "UI calls must run inside the window update")
	return &active_state.frame
}

@(private)
Frame_State :: struct {
	frame: Frame,
	update: Update,
	rects: [dynamic]Rect_Context,
	text: fonts.Store,
	identities: Identity_Store,
}

@(private)
active_state: ^Frame_State

@(private)
destroy_frame_state :: proc(state: ^Frame_State) {
	delete(state.frame.surfaces)
	delete(state.rects)
	destroy_identities(&state.identities)
	// The platform has already released its renderer and all GPU images.
	fonts.destroy(&state.text, nil)
}

@(private)
build_frame :: proc(renderer: platform.Renderer, elapsed: f64, size: [2]f32, user_data: rawptr) -> []Surface {
	assert(active_state == nil, "Window updates cannot be nested")
	state := cast(^Frame_State)user_data
	active_state = state
	defer { active_state = nil }
	state.frame.time = elapsed
	state.frame.size = size
	state.frame.renderer = renderer
	state.frame.scale = platform.pixel_scale(renderer)
	clear(&state.frame.surfaces)
	assert(valid_length(size.x) && valid_length(size.y), "Invalid viewport size")
	clear(&state.rects)
	identity_begin_frame(&state.identities)
	root := Rect{size = size}
	append(&state.rects, Rect_Context{bounds = root, remaining = root})
	if state.update != nil {
		state.update()
	}
	assert(len(state.rects) == 1, "Unclosed rects at end of update")
	identity_end_frame(&state.identities)
	assert(fonts.flush(&state.text, renderer) == .None, "Could not upload text atlas")
	return state.frame.surfaces[:]
}
