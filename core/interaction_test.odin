package ui

import "core:testing"
import "core:mem"

@(private)
interaction_pipeline :: proc(t: ^testing.T) {
	state := Frame_State{update = layer_hit_scene}
	defer destroy_frame_state(&state)
	layer_hit_passthrough = false
	state.frame.input = {mouse_inside = true, mouse_position = {20, 20}}
	build_frame(nil, 0, {100, 100}, &state)
	testing.expect_value(t, layer_hits, [3]bool{}) // No prior geometry.
	surfaces := build_frame(nil, 1, {100, 100}, &state)
	testing.expect_value(t, layer_hits, [3]bool{true, true, false})
	testing.expect_value(t, state.interaction.direct_hover, layer_ids[1])
	testing.expect_value(t, surfaces[0].background, Color{1, 0, 0, 1})
	testing.expect_value(t, surfaces[1].background, Color{0, 0, 1, 1})
	testing.expect_value(t, surfaces[2].background, Color{0, 1, 0, 1}) // Higher z beats later declaration.
	layer_hit_passthrough = true
	build_frame(nil, 2, {100, 100}, &state)
	build_frame(nil, 3, {100, 100}, &state)
	testing.expect_value(t, state.interaction.direct_hover, layer_ids[2])
	testing.expect_value(t, layer_hits, [3]bool{true, false, true})
	// A clip-escaped popup can be hovered outside its parent's own bounds;
	// that parent must not report secondary hover outside its bounds.
	state.frame.input.mouse_position = {45, 45}
	layer_hit_passthrough = false
	build_frame(nil, 4, {100, 100}, &state)
	build_frame(nil, 5, {100, 100}, &state)
	testing.expect_value(t, layer_hits, [3]bool{false, true, false})
	// Both surface arrays and hit buffers retain capacity after warm-up.
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	build_frame(nil, 6, {100, 100}, &state)
	testing.expect_value(t, tracking.total_allocation_count, i64(0))
}

@(private) layer_ids: [3]Identity
@(private) layer_hits: [3]bool
@(private) layer_hit_passthrough: bool

@(private)
layer_hit_scene :: proc() {
	open_rect_at(Rect{{0, 0}, {40, 40}}, key = 1)
	layer_ids[0], layer_hits[0] = current_identity(), hovered()
	paint(color = {1, 0, 0, 1})
	open_clip()
	open_layer(10, escape_clip = true)
	open_rect_at(Rect{{10, 10}, {40, 40}}, key = 2)
	set_hit_test(!layer_hit_passthrough)
	layer_ids[1], layer_hits[1] = current_identity(), hovered()
	paint(color = {0, 1, 0, 1})
	close_rect()
	close_layer()
	open_rect_at(Rect{{10, 10}, {40, 40}}, key = 3)
	layer_ids[2], layer_hits[2] = current_identity(), hovered()
	paint(color = {0, 0, 1, 1})
	close_rect()
	close_clip()
	close_rect()
}

@(private)
scroll_pipeline :: proc(t: ^testing.T) {
	state := Frame_State{update = scroll_scene}
	defer destroy_frame_state(&state)
	scroll_small = false
	state.frame.input = {mouse_inside = true, mouse_position = {10, 10}}
	build_frame(nil, 0, {100, 100}, &state)
	state.frame.input.scroll_delta = {0, 150}
	build_frame(nil, 1, {100, 100}, &state)
	testing.expect_value(t, scroll_offsets[1], [2]f32{0, 100})
	testing.expect_value(t, scroll_offsets[0], [2]f32{0, 50}) // Inner consumed 100, outer receives 50.
	testing.expect_value(t, state.frame.input.scroll_delta, [2]f32{0, 150}) // Raw data unmodified.
	state.frame.input.scroll_delta = {}
	build_frame(nil, 2, {100, 280}, &state)
	testing.expect_value(t, scroll_offsets[0], [2]f32{0, 20}) // Resize clamps retained offset.
	scroll_small = true
	build_frame(nil, 3, {100, 100}, &state)
	testing.expect_value(t, scroll_offsets, [2][2]f32{}) // Content shrink clamps both axes.
	state.update = nil
	build_frame(nil, 4, {100, 100}, &state)
	testing.expect_value(t, len(state.interaction.scrolls), 0)
}

@(private) scroll_offsets: [2][2]f32
@(private) scroll_small: bool
@(private)
scroll_scene :: proc() {
	open_scroll({100, 80 if scroll_small else 300}, key = 1)
	scroll_offsets[0] = current_scroll().offset
	open_rect(.Top, 60)
	open_scroll({100, 40 if scroll_small else 160}, key = 2)
	scroll_offsets[1] = current_scroll().offset
	paint()
	close_scroll()
	close_rect()
	close_scroll()
}

@(private)
focus_pipeline :: proc(t: ^testing.T) {
	state := Frame_State{update = focus_scene}
	defer destroy_frame_state(&state)
	focus_modal, focus_remove = false, false
	build_frame(nil, 0, {100, 100}, &state)
	state.frame.input.keys_pressed = {.Tab}
	build_frame(nil, 1, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, focus_ids[0])
	state.frame.input.text.handled_keys = {.Tab}
	build_frame(nil, 1.5, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, focus_ids[0]) // IME-owned Tab must not leave the field.
	state.frame.input.text.handled_keys = {}
	build_frame(nil, 2, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, focus_ids[2]) // Disabled middle button skipped.
	state.frame.input.modifiers = {.Shift}
	build_frame(nil, 3, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, focus_ids[0])
	state.frame.input = {mouse_inside = true, mouse_position = {20, 85}, mouse_buttons = {.Left}}
	build_frame(nil, 4, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, focus_ids[2])
	testing.expect(t, focus_parent_active)
	state.frame.input = {}
	focus_modal = true
	build_frame(nil, 5, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, focus_ids[3])
	state.frame.input.keys_pressed = {.Tab}
	build_frame(nil, 6, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, focus_ids[4])
	build_frame(nil, 7, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, focus_ids[3]) // Wrap stays in fence.
	state.frame.input = {}
	focus_modal = false
	build_frame(nil, 8, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, focus_ids[2]) // Restore original owner.
	focus_remove = true
	build_frame(nil, 9, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, Identity{})
}

@(private) focus_ids: [5]Identity
@(private) focus_modal, focus_remove, focus_parent_active: bool
@(private)
focus_scene :: proc() {
	open_rect_at(Rect{{0, 0}, {100, 100}}, key = 1)
	focus_parent_active = focused()
	for i in 0..<3 {
		if i == 2 && focus_remove { continue }
		open_rect(.Top, 30, key = i)
		focus_ids[i] = current_identity()
		focusable(i != 1)
		paint()
		close_rect()
	}
	close_rect()
	if focus_modal {
		open_layer(10)
		open_rect_at(Rect{{10, 10}, {80, 80}}, key = 2)
		focus_fence()
		for i in 0..<2 {
			open_rect(.Top, 30, key = i)
			focus_ids[3 + i] = current_identity()
			focusable()
			paint()
			close_rect()
		}
		close_rect()
		close_layer()
	}
}

// A wheel delta and a focus change in the same snapshot must reveal using the
// newly scrolled position rather than applying yesterday's geometry twice.
@(private)
scroll_focus_pipeline :: proc(t: ^testing.T) {
	state := Frame_State{update = scroll_focus_scene}
	defer destroy_frame_state(&state)
	build_frame(nil, 0, {100, 100}, &state)
	state.frame.input = {keys_pressed = {.Tab}}
	build_frame(nil, 1, {100, 100}, &state)
	state.frame.input = {keys_pressed = {.Tab}, scroll_delta = {0, 150}, mouse_inside = true, mouse_position = {10, 10}}
	build_frame(nil, 2, {100, 100}, &state)
	testing.expect_value(t, scroll_focus_offset, f32(100))
	previous := state.interaction.focused
	state.frame.input = {keys_pressed = {.Tab}, modifiers = {.Control}}
	build_frame(nil, 3, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, previous) // Ctrl-Tab belongs to application policy.
}

@(private) scroll_focus_offset: f32
@(private)
scroll_focus_scene :: proc() {
	open_scroll({100, 300})
	scroll_focus_offset = current_scroll().offset.y
	for i in 0..<3 {
		open_rect(.Top, 100, key = i)
		focusable()
		paint()
		close_rect()
	}
	close_scroll()
}

@(private)
nested_focus_pipeline :: proc(t: ^testing.T) {
	state := Frame_State{update = nested_focus_scene}
	defer destroy_frame_state(&state)
	nested_fence_depth = 0
	build_frame(nil, 0, {100, 100}, &state)
	state.frame.input.keys_pressed = {.Tab}
	build_frame(nil, 1, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, nested_focus_ids[0])
	state.frame.input = {}
	nested_fence_depth = 1
	build_frame(nil, 2, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, nested_focus_ids[1])
	nested_fence_depth = 2
	build_frame(nil, 3, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, nested_focus_ids[2])
	nested_fence_depth = 1
	build_frame(nil, 4, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, nested_focus_ids[1])
	nested_fence_depth = 2
	build_frame(nil, 5, {100, 100}, &state)
	nested_fence_depth = 0 // Close both fences in one frame.
	build_frame(nil, 6, {100, 100}, &state)
	testing.expect_value(t, state.interaction.focused, nested_focus_ids[0])
	testing.expect_value(t, len(state.interaction.fences), 0)
}

@(private) nested_fence_depth: int
@(private) nested_focus_ids: [3]Identity
@(private)
nested_focus_scene :: proc() {
	open_rect_at(Rect{size = {100, 100}}, key = 0)
	focusable()
	nested_focus_ids[0] = current_identity()
	close_rect()
	for depth in 0..<nested_fence_depth {
		open_layer(i32(depth + 1))
		open_rect_at(Rect{size = {100, 100}}, key = depth + 1)
		focus_fence()
		focusable()
		nested_focus_ids[depth + 1] = current_identity()
	}
	for _ in 0..<nested_fence_depth {
		close_rect()
		close_layer()
	}
}
