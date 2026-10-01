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
Key :: input.Key
Keys :: input.Keys
Modifier :: input.Modifier
Modifiers :: input.Modifiers
Lock :: input.Lock
Locks :: input.Locks

// The framework clears surfaces before each update, retaining its capacity.
// Append low-level primitives here; do not clear/reorder/overwrite during update
// or retain the slice across updates. The framework applies clips and layers.
Frame :: struct {
	window:     Window, // Zero for a headless capture session.
	time:       f64, // Monotonic application time, shared by every builder in a cycle.
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
	clips: [dynamic]Clip_Scope,
	surface_cursor: int,
	layers: [dynamic]Layer_Scope,
	surface_runs: [dynamic]Surface_Run,
	layer_buckets: [dynamic]Layer_Bucket,
	surface_scratch: [dynamic]Surface,
	interaction: Interaction_Store,
}

@(private)
active_state: ^Frame_State

@(private)
destroy_frame_state :: proc(state: ^Frame_State) {
	delete(state.frame.surfaces)
	delete(state.rects)
	delete(state.clips)
	delete(state.layers)
	delete(state.surface_runs)
	delete(state.layer_buckets)
	delete(state.surface_scratch)
	destroy_interaction(&state.interaction)
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
	state.surface_cursor = 0
	clear(&state.clips)
	clear(&state.layers)
	clear(&state.surface_runs)
	interaction_begin()
	assert(valid_length(size.x) && valid_length(size.y), "Invalid viewport size")
	clear(&state.rects)
	identity_begin_frame(&state.identities)
	root := Rect{size = size}
	append(&state.rects, Rect_Context{bounds = root, remaining = root, hit_index = register_hit(current_identity(), root)})
	if state.update != nil {
		state.update()
	}
	assert(len(state.rects) == 1, "Unclosed rects at end of update")
	assert(len(state.clips) == 0, "Unclosed clips at end of update")
	assert(len(state.layers) == 0, "Unclosed layers at end of update")
	flush_surface_state()
	order_layers()
	identity_end_frame(&state.identities)
	interaction_end()
	assert(fonts.flush(&state.text, renderer) == .None, "Could not upload text atlas")
	return state.frame.surfaces[:]
}
