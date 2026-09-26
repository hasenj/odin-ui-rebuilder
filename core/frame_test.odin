package ui

import "core:testing"
import "core:mem"

// Exercise the public construction API through a complete frame build, including
// a transparent layout-only parent and interleaved low-level drawing.
@(test)
container_frame_pipeline :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	state := Frame_State{update = layout_scene}
	defer destroy_frame_state(&state)
	surfaces := build_frame(nil, 1, {200, 100}, &state)
	testing.expect(t, active_state == nil)
	testing.expect_value(t, len(surfaces), 5)
	expected_positions := [?][2]f32{{0, 0}, {3, 4}, {3, 10}, {99, 88}, {25, 3}}
	expected_sizes := [?][2]f32{{37, 22}, {10, 4}, {14, 6}, {3, 4}, {8, 9}}
	for surface, i in surfaces {
		testing.expect_value(t, surface.position, expected_positions[i])
		testing.expect_value(t, surface.size, expected_sizes[i])
	}
	testing.expect_value(t, surfaces[0].corner_radius, f32(5))
	testing.expect_value(t, surfaces[3].background, Color{0, 0, 1, 1})
	// A second build reuses storage and emits the same geometry in the new viewport.
	allocations_before := tracking.total_allocation_count
	surfaces = build_frame(nil, 2, {300, 200}, &state)
	allocations_after := tracking.total_allocation_count
	testing.expect_value(t, allocations_after, allocations_before)
	testing.expect_value(t, len(surfaces), 5)
	testing.expect_value(t, state.tree.sizes[0], [2]f32{300, 200})
	testing.expect_value(t, surfaces[4].position, [2]f32{25, 3})
	state.update = nil
	surfaces = build_frame(nil, 3, {100, 50}, &state)
	testing.expect_value(t, len(surfaces), 0)
	testing.expect_value(t, len(state.tree.nodes), 1)
	testing.expect(t, active_state == nil)
}

@(private)
layout_scene :: proc() {
	container_open({layout = .Row, padding = {2, 3, 4, 5}, gap = 7,
		background = {0.1, 0.1, 0.1, 1}, corner_radius = 5})
	{
		container_open({padding = insets(1), gap = 2})
		{
			container_open({width = fixed(10), height = fixed(4), background = {1, 0, 0, 1}})
			container_close()
			container_open({width = fixed(14), height = fixed(6), background = {0, 1, 0, 1}})
			container_close()
		}
		container_close()
		append(&current_frame().surfaces, Surface{position = {99, 88}, size = {3, 4}, background = {0, 0, 1, 1}})
		container_open({width = fixed(8), height = fixed(9), background = {1, 1, 0, 1}})
		container_close()
	}
	container_close()
}
