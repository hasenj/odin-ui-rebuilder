package ui

import "core:testing"
import "core:mem"

@(private) layout_test_ids: [3]Identity
@(private) layout_test_values: [3]f32
@(private) layout_test_hover: [3]bool
@(private) layout_test_order := [3]int{0, 1, 2}
@(private) layout_test_calls, layout_test_clicks: int
@(private) layout_test_bottom: bool
@(private) layout_test_result: Rect

// Public builder -> layout passes -> surface and hit geometry. Run serially
// with the other frame tests because the UI context is deliberately implicit.
@(private)
local_layout_pipeline :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	state := Frame_State{update = local_layout_scene}
	defer destroy_frame_state(&state)
	layout_test_order = {0, 1, 2}
	layout_test_calls, layout_test_clicks = 0, 0
	layout_test_bottom = false
	surfaces := build_frame(nil, 0, {200, 100}, &state)
	testing.expect_value(t, layout_test_calls, 1)
	testing.expect_value(t, len(surfaces), 5)
	testing.expect_value(t, surfaces[0].size, [2]f32{200, 40})
	testing.expect(t, surfaces[1].clip.enabled)
	testing.expect_value(t, surfaces[1].clip.max, [2]f32{200, 100})
	positions := [?][2]f32{{10, 10}, {60, 5}, {110, 15}}
	sizes := [?][2]f32{{40, 20}, {40, 30}, {80, 10}}
	ids := layout_test_ids
	for i in 0..<3 {
		testing.expect_value(t, surfaces[i + 1].position, positions[i])
		testing.expect_value(t, surfaces[i + 1].size, sizes[i])
		entry := state.interaction.previous[state.interaction.previous_by_id[ids[i]]]
		testing.expect_value(t, entry.bounds, Rect{positions[i], sizes[i]})
	}
	testing.expect_value(t, surfaces[4].position, [2]f32{0, 40}) // Immediate paint follows resolved scope.
	testing.expect_value(t, surfaces[4].size, [2]f32{200, 60})
	state.frame.input = {mouse_inside = true, mouse_position = {70, 10}, mouse_pressed = {.Left}}
	build_frame(nil, 0.1, {200, 100}, &state)
	testing.expect_value(t, layout_test_calls, 2)
	testing.expect_value(t, layout_test_clicks, 1) // No callback replay in measurement/placement.
	testing.expect_value(t, state.interaction.focused, ids[1])
	testing.expect_value(t, layout_test_hover, [3]bool{false, true, false})
	testing.expect(t, layout_test_values[1] > 0 && layout_test_values[1] < 1)
	// Explicit IDs keep animation and focus through changed declaration order.
	layout_test_order = {2, 1, 0}
	state.frame.input = {}
	build_frame(nil, 0.2, {300, 100}, &state)
	testing.expect_value(t, layout_test_ids, ids)
	testing.expect_value(t, state.interaction.focused, ids[1])
	testing.expect(t, layout_test_values[1] > 0)
	// Buffers/maps have warmed; resize/reorder must reuse their storage.
	before := tracking.total_allocation_count
	build_frame(nil, 0.3, {220, 100}, &state)
	testing.expect_value(t, tracking.total_allocation_count, before)
	layout_test_bottom = true
	build_frame(nil, 0.4, {200, 100}, &state)
	testing.expect_value(t, layout_test_result, Rect{{0, 60}, {200, 40}})
	build_frame(nil, 0.5, {0, 0}, &state)
	testing.expect_value(t, layout_test_result.size, [2]f32{})
	state.update = nil
	build_frame(nil, 1, {200, 100}, &state)
	for id in ids { testing.expect(t, !state.identities.nodes[id.index - 1].alive) }
	testing.expect_value(t, len(state.identities.animations), 0)
}

@(private)
local_layout_scene :: proc() {
	layout_test_calls += 1
	open_clip()
	open_layer(3)
	open_layout(.Bottom if layout_test_bottom else .Top, {flow = .Row, gap = 10, padding = {5, 10}, align = .Center})
	paint(color = {0.1, 0.1, 0.1, 1})
	for i in layout_test_order {
		width := layout_fixed(80 if i == 2 else 40)
		heights := [3]f32{20, 30, 10}
		open_box({width = width, height = layout_fixed(heights[i])}, key = i)
		layout_test_ids[i] = current_identity()
		focusable()
		layout_test_hover[i] = hovered()
		if hovered() && .Left in current_frame().input.mouse_pressed { layout_test_clicks += 1 }
		layout_test_values[i] = animate_f32(1 if hovered() else 0)
		paint(color = {layout_test_values[i], 0.3, 0.5, 1})
		close_box()
	}
	err: Text_Error
	layout_test_result, err = close_layout()
	assert(err == .None)
	close_layer()
	close_clip()
	open_layer(4)
	paint()
	close_layer()
}

@(private) stretch_menu, stretch_row: Rect
@(private)
local_layout_stretch_pipeline :: proc(t: ^testing.T) {
	state := Frame_State{update = local_layout_stretch_scene}
	defer destroy_frame_state(&state)
	surfaces := build_frame(nil, 0, {300, 200}, &state)
	testing.expect_value(t, stretch_menu.size, [2]f32{108, 66})
	// All menu rows match the widest content plus their own padding, not the
	// entire 300-point enclosing rect. Their children keep natural fixed widths.
	for index in ([?]int{1, 3, 5}) { testing.expect_value(t, surfaces[index].size, [2]f32{92, 16}) }
	testing.expect_value(t, surfaces[2].size, [2]f32{40, 10})
	testing.expect_value(t, stretch_row, Rect{{246, 66}, {54, 60}})
	testing.expect_value(t, surfaces[7].size, [2]f32{20, 50}) // Content-height child stretches.
	testing.expect_value(t, surfaces[8].size, [2]f32{20, 30}) // Explicit cross size wins.
	// Extra width is unused; a smaller enclosure constrains each item, without
	// dividing available main-axis space between siblings.
	surfaces = build_frame(nil, 1, {70, 200}, &state)
	testing.expect_value(t, stretch_menu.size, [2]f32{70, 66})
	for index in ([?]int{1, 3, 5}) { testing.expect_value(t, surfaces[index].size.x, f32(54)) }
	surfaces = build_frame(nil, 2, {30, 200}, &state)
	testing.expect_value(t, stretch_row.size.x, f32(30))
	testing.expect_value(t, surfaces[7].size.x, f32(20))
	testing.expect_value(t, surfaces[8].size.x, f32(20)) // Row overflows; neither sibling is shrunk to 8.
	build_frame(nil, 3, {70, 40}, &state)
	testing.expect_value(t, stretch_menu.size, [2]f32{70, 40}) // Root respects the available height too.
	testing.expect_value(t, stretch_row.size.y, f32(0)) // No height remains after the cut.
}

@(private)
local_layout_stretch_scene :: proc() {
	open_layout(.Top, {gap = 4, padding = {5, 8}, stretch = true})
	paint()
	for width in ([?]f32{40, 80, 50}) {
		open_box({padding = {3, 6}})
		paint()
		open_box({width = layout_fixed(width), height = layout_fixed(10)})
		paint()
		close_box()
		close_box()
	}
	err: Text_Error
	stretch_menu, err = close_layout()
	assert(err == .None)
	open_layout(.Right, {flow = .Row, height = layout_fixed(60), padding = {5, 5}, gap = 4, stretch = true})
	open_box({width = layout_fixed(20)})
	paint()
	open_box({height = layout_fixed(10)})
	close_box()
	close_box()
	open_box({width = layout_fixed(20), height = layout_fixed(30)})
	paint()
	close_box()
	stretch_row, err = close_layout()
	assert(err == .None)
}
