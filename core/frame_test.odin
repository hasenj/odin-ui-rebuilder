package ui

import "core:testing"
import "core:mem"
import "core:path/filepath"

// Full public API -> emitted surfaces, including nested cuts, padding, image
// tint defaults, original bounds, and interleaved low-level drawing.
@(test)
rect_frame_pipeline :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	state := Frame_State{update = rect_scene}
	defer destroy_frame_state(&state)
	surfaces := build_frame(nil, 1, {200, 100}, &state)
	testing.expect(t, active_state == nil)
	testing.expect_value(t, len(surfaces), 9)
	expected_positions := [?][2]f32{{0, 0}, {5, 2}, {9, 4}, {39, 4}, {5, 86}, {157, 22}, {160, 25}, {99, 88}, {5, 22}}
	expected_sizes := [?][2]f32{{200, 100}, {192, 20}, {30, 16}, {154, 16}, {192, 10}, {40, 64}, {34, 58}, {3, 4}, {152, 64}}
	for surface, i in surfaces {
		testing.expect_value(t, surface.position, expected_positions[i])
		testing.expect_value(t, surface.size, expected_sizes[i])
	}
	testing.expect_value(t, surfaces[1].corner_radius, f32(8))
	testing.expect_value(t, surfaces[2].corner_radius, f32(3))
	testing.expect_value(t, surfaces[2].image, Image{7, 2})
	testing.expect_value(t, surfaces[2].background, Color{1, 1, 1, 1})
	testing.expect_value(t, surfaces[3].corner_radius, f32(0))
	testing.expect_value(t, surfaces[7].background, Color{0, 0, 1, 1})
	// Resizing rebuilds from the new viewport without allocating after warm-up.
	allocations_before := tracking.total_allocation_count
	surfaces = build_frame(nil, 2, {300, 200}, &state)
	allocations_after := tracking.total_allocation_count
	testing.expect_value(t, allocations_after, allocations_before)
	testing.expect_value(t, surfaces[0].size, [2]f32{300, 200})
	testing.expect_value(t, surfaces[8].size, [2]f32{252, 164})
	testing.expect_value(t, len(state.rects), 1)
	state.update = nil
	surfaces = build_frame(nil, 3, {100, 50}, &state)
	testing.expect_value(t, len(surfaces), 0)
	testing.expect_value(t, state.rects[0].remaining, Rect{size = {100, 50}})
	testing.expect(t, active_state == nil)
	// Frame construction has one implicit UI context. Exercise the other scenes
	// sequentially rather than asking the test runner to build windows in parallel.
	exhausted_rects(t)
	deep_rect_scopes(t)
	empty_rect_text(t)
	hover_rects(t)
	identity_animation_pipeline(t)
	clip_pipeline(t)
	when ODIN_OS == .Darwin { capture_pipeline(t) }
}

// Frame input -> nested/padded rect queries -> paint, including shared edges,
// pointer leave and resized/exhausted cuts. No identities or prior-frame state.
@(private)
hover_rects :: proc(t: ^testing.T) {
	state := Frame_State{update = hover_scene}
	defer destroy_frame_state(&state)
	Case :: struct {pointer, viewport: [2]f32, inside: bool, hits: [6]bool}
	cases := [?]Case{
		{{5, 10}, {100, 100}, true, {true, false, true, false, false, false}},
		{{10, 0}, {100, 100}, true, {true, true, true, false, false, false}},
		{{29, 20}, {100, 100}, true, {false, false, false, true, false, false}},
		{{30, 20}, {100, 100}, true, {false, false, false, false, true, false}},
		{{100, 30}, {100, 100}, true, {}},
		{{30, 100}, {100, 100}, true, {}},
		{{-1, 10}, {100, 100}, true, {}},
		{{15, 10}, {100, 100}, false, {}},
		{{15, 10}, {20, 15}, true, {true, true, true, false, false, false}},
		{{0, 0}, {}, true, {}},
	}
	for item in cases {
		state.frame.input = {mouse_position = item.pointer, mouse_inside = item.inside}
		surfaces := build_frame(nil, 0, item.viewport, &state)
		testing.expect_value(t, len(surfaces), len(item.hits))
		for surface, i in surfaces {
			testing.expect_value(t, surface.background.r == 1, item.hits[i])
		}
	}
}

@(private)
hover_scene :: proc() {
	open_rect(.Top, 20)
	{
		paint_hover(hovered())
		pad4(0, 0, 0, 10)
		paint_hover(hovered())
		paint_hover(hovered(current_bounds()))
	}
	close_rect()
	open_rect(.Left, 30)
	paint_hover(hovered())
	close_rect()
	paint_hover(hovered())
	open_rect(.Top, 0)
	paint_hover(hovered())
	close_rect()
}

@(private)
paint_hover :: proc(hit: bool) {
	paint(color = {1 if hit else 0, 0, 0, 1})
}

@(private)
rect_scene :: proc() {
	root := current_bounds()
	paint(color = hsl(240, 50, 50))
	pad4(2, 3, 4, 5)
	assert(current_bounds() == root)
	open_rect(.Top, 20)
	{
		bounds := current_bounds()
		paint(color = {1, 0, 0, 1}, corners = 8)
		pad2(2, 4)
		assert(current_bounds() == bounds)
		open_rect(.Left, 30)
		{
			paint(img = {7, 2}, corners = 3)
		}
		close_rect()
		paint(color = {0, 1, 0, 1})
	}
	close_rect()
	open_rect(.Bottom, 10)
	{
		paint(color = {0, 0, 1, 1})
	}
	close_rect()
	open_rect(.Right, 40)
	{
		paint(color = {1, 1, 0, 1})
		pad(3)
		paint(color = {1, 0, 1, 1})
	}
	close_rect()
	append(&current_frame().surfaces, Surface{position = {99, 88}, size = {3, 4}, background = {0, 0, 1, 1}})
	paint(color = {0, 1, 1, 1})
	assert(current_bounds() == root)
}

@(private)
exhausted_rects :: proc(t: ^testing.T) {
	state := Frame_State{update = exhausted_scene}
	defer destroy_frame_state(&state)
	surfaces := build_frame(nil, 0, {10, 8}, &state)
	expected := [?]Rect{
		{size = {10, 0}},
		{size = {10, 8}},
		{size = {10, 8}},
		{position = {10, 8}},
		{size = {0, 8}},
		{size = {0, 8}},
		{},
	}
	testing.expect_value(t, len(surfaces), len(expected))
	for surface, i in surfaces {
		testing.expect_value(t, Rect{surface.position, surface.size}, expected[i])
	}
	// A zero viewport remains valid through padding and oversized cuts.
	surfaces = build_frame(nil, 0, {}, &state)
	for surface in surfaces {
		testing.expect_value(t, surface.position, [2]f32{})
		testing.expect_value(t, surface.size, [2]f32{})
	}
}

@(private)
exhausted_scene :: proc() {
	open_rect(.Top, 0)
	paint()
	close_rect()
	paint()
	open_rect(.Right, 99)
	paint()
	pad4(9, 1, 3, 12)
	paint()
	close_rect()
	paint()
	open_rect(.Bottom, 99)
	paint()
	close_rect()
	paint()
}

@(private)
deep_rect_scopes :: proc(t: ^testing.T) {
	state := Frame_State{update = deep_rect_scene}
	defer destroy_frame_state(&state)
	surfaces := build_frame(nil, 0, {100, 100}, &state)
	testing.expect_value(t, len(surfaces), 1)
	testing.expect_value(t, surfaces[0].size, [2]f32{100, 100})
	testing.expect_value(t, len(state.rects), 1)
	// All child contexts are discarded; only the exhausted root remains.
	testing.expect_value(t, state.rects[0].remaining.size, [2]f32{100, 0})
}

@(private)
deep_rect_scene :: proc() {
	for _ in 0..<10_000 {
		open_rect(.Top, 100)
	}
	paint()
	for _ in 0..<10_000 {
		close_rect()
	}
}

// Regression for shrinking app5: after height runs out, repeated line cuts
// share an origin. They must not emit overlapping glyphs at that origin.
@(private)
empty_rect_text :: proc(t: ^testing.T) {
	state := Frame_State{update = empty_rect_text_scene}
	defer destroy_frame_state(&state)
	viewports := [?][2]f32{{200, 100}, {200, 0}, {0, 100}, {0, 0}}
	for viewport in viewports {
		surfaces := build_frame(nil, 0, viewport, &state)
		testing.expect_value(t, len(surfaces), 0)
		testing.expect_value(t, len(state.text.pages), 0)
		testing.expect_value(t, len(state.rects), 1)
	}
}

@(private)
empty_rect_text_scene :: proc() {
	font, loaded := find_font("test-body")
	if !loaded {
		path, _ := filepath.join({filepath.dir(#location().file_path), "../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
		defer delete(path)
		err: Text_Error
		font, err = load_font(path, name = "test-body")
		assert(err == .None)
	}
	// Zero-width cuts should also be invisible, with full metrics preserved.
	open_rect(.Left, 0)
	{
		expected, _ := measure_text("invisible", font)
		actual, err := text("invisible", font)
		assert(err == .None && actual == expected)
		wrapped, wrap_error := layout_text("invisible wrapped text", "test-body", max_width = 50)
		assert(wrap_error == .None && wrapped.line_count > 1)
		assert(draw_text_layout(wrapped, align = .End) == .None)
		fitted, fit_error := layout_text_fit("invisible", font, max_width = expected.width * 0.75)
		assert(fit_error == .None && fitted.size < 16 && !fitted.overflow)
		assert(draw_text_layout(fitted, align = .Center, valign = .Center) == .None)
		multiline, multiline_error := layout_text_fit("invisible invisible", "test-body",
			max_width = expected.width * 0.5 + 0.1, max_height = 0, wrap_at_min = true)
		assert(multiline_error == .None && multiline.line_count == 2 && multiline.overflow)
		assert(draw_text_layout(multiline, align = .Center, valign = .Center) == .None)
	}
	close_rect()
	open_rect(.Top, current_rect().size.y)
	close_rect()
	for _ in 0..<4 {
		open_rect(.Top, 30)
		{
			pad(4)
			expected, _ := measure_text("exhausted line", font, size = 20)
			actual, err := text("exhausted line", "test-body", size = 20)
			assert(err == .None && actual == expected)
			_, err = text("bad font", "missing")
			assert(err == .Invalid_Font)
		}
		close_rect()
	}
}
