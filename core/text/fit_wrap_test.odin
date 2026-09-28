package text

import "core:testing"
import "core:mem"
import "core:math"
import "core:path/filepath"
import "../primitives"

// Real font/shaping -> shrink/wrap -> centered surfaces, at both pixel scales.
// Measurement must agree with drawing and reuse desired-size atlas bitmaps.
@(test)
fit_wrap_pipeline :: proc(t: ^testing.T) {
	root := filepath.dir(#location().file_path)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	store: Store
	Case :: struct {path, value, first, second: string, weight: f32}
	cases := []Case{
		{"../../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf", "Save all changes", "Save all", "changes", 600},
		{"../../examples/assets/fonts/Amiri-Regular.ttf", "السَّلَامُ عَلَيْكُمْ", "السَّلَامُ", "عَلَيْكُمْ", 0},
	}
	surfaces: [dynamic]primitives.Surface
	for item in cases {
		path, _ := filepath.join({root, item.path})
		font, load_error := load(&store, path)
		delete(path)
		assert(load_error == .None)
		for scale in ([]f32{1, 2}) {
			full, _ := measure(&store, font, item.value, 24, scale, item.weight)
			first, _ := measure(&store, font, item.first, 24, scale, item.weight)
			second, _ := measure(&store, font, item.second, 24, scale, item.weight)
			width := max(first.width, second.width) * 0.5 + 0.1
			testing.expect(t, width < full.width * 0.5)
			// The default remains single-line. Height can shrink even a wide label.
			single, err := fit(&store, font, item.value, 24, scale, item.weight, width)
			assert(err == .None)
			testing.expect(t, single.line_count == 1 && single.overflow && single.size == 12)
			short, short_error := fit(&store, font, item.value, 24, scale, item.weight, full.width,
				max_height = full.height * 0.75, wrap_at_min = true)
			assert(short_error == .None)
			testing.expect(t, short.line_count == 1 && !short.overflow)
			testing.expect(t, math.abs(short.size - 18) < 0.0001)
			testing.expect(t, math.abs(short.height - full.height * 0.75) < 0.0001)
			// Exact minimum-size fit must stay on one line.
			edge, _ := fit(&store, font, item.value, 24, scale, item.weight, full.width * 0.5,
				max_height = full.height * 0.5, wrap_at_min = true)
			testing.expect(t, edge.line_count == 1 && edge.size == 12 && !edge.overflow)

			wrapped, wrap_error := fit(&store, font, item.value, 24, scale, item.weight, width,
				max_height = full.height, wrap_at_min = true)
			assert(wrap_error == .None)
			testing.expect_value(t, wrapped.line_count, 2)
			testing.expect_value(t, wrapped.size, f32(12))
			testing.expect_value(t, wrapped.height, full.height)
			testing.expect(t, !wrapped.overflow && wrapped.width <= width)
			testing.expect(t, math.abs(wrapped.width - max(first.width, second.width) * 0.5) < 0.0001)
			limited, _ := fit(&store, font, item.value, 24, scale, item.weight, width,
				max_height = wrapped.height - 0.01, wrap_at_min = true)
			testing.expect(t, limited.overflow && limited.height == wrapped.height && limited.size == 12)
			zero_height, _ := fit(&store, font, item.value, 24, scale, item.weight, full.width,
				max_height = 0, wrap_at_min = true)
			testing.expect(t, zero_height.overflow && zero_height.line_count == 1 && zero_height.size == 12)
			zero_width, _ := fit(&store, font, item.value, 24, scale, item.weight, 0,
				max_height = full.height, wrap_at_min = true)
			testing.expect(t, zero_width.overflow && zero_width.size == 12)
			custom, _ := fit(&store, font, item.value, 24, scale, item.weight, max(first.width, second.width) * 0.75 + 0.1,
				min_scale = 0.75, max_height = full.height * 1.5, wrap_at_min = true)
			testing.expect(t, custom.line_count == 2 && custom.size == 18 && !custom.overflow)

			// Rasterization and placement use the original 24-point font. Both
			// lines align independently and the entire block is vertically centered.
			run, _ := resolve_layout(&store, wrapped._request)
			testing.expect_value(t, run.pixel_size, i32(24 * scale * 64))
			quads, prepare_error := prepare_quads(&store, run)
			assert(prepare_error == .None)
			for &page, i in store.pages { page.image = {u32(i + 1), 1} }
			clear(&surfaces)
			height := wrapped.height + 12
			err = draw_layout(&store, nil, wrapped, {10, 20}, {width, height}, {1, 1, 1, 1}, &surfaces, .Center, .Center)
			assert(err == .None)
			divisor := scale / 0.5
			for quad, i in quads {
				origin := [2]f32{10 + (width - run.lines[quad.line].width / divisor) / 2, 26}
				testing.expect_value(t, surfaces[i].position, origin + quad.position / divisor)
				testing.expect_value(t, surfaces[i].size, quad.size / divisor)
			}
			shapes, bidis, builds := store.shape_calls, store.bidi_calls, store.geometry_builds
			allocations := tracking.total_allocation_count
			for _ in 0..<50 {
				again, error := fit(&store, font, item.value, 24, scale, item.weight, width,
					max_height = full.height, wrap_at_min = true)
				assert(error == .None)
				clear(&surfaces)
				assert(draw_layout(&store, nil, again, {10, 20}, {width, height}, {1, 1, 1, 1}, &surfaces, .Center, .Center) == .None)
			}
			testing.expect_value(t, store.shape_calls, shapes)
			testing.expect_value(t, store.bidi_calls, bidis)
			testing.expect_value(t, store.geometry_builds, builds)
			testing.expect_value(t, tracking.total_allocation_count, allocations)
			glyphs := len(store.fonts[int(font) - 1].glyphs)
			// New wrap widths reuse paragraph shaping and the existing bitmaps.
			for i in 0..<30 {
				changing, error := fit(&store, font, item.value, 24, scale, item.weight, width + f32(i) * 0.1,
					max_height = height, wrap_at_min = true)
				assert(error == .None)
				clear(&surfaces)
				assert(draw_layout(&store, nil, changing, {}, {width + f32(i) * 0.1, height}, {}, &surfaces) == .None)
			}
			testing.expect_value(t, store.shape_calls, shapes)
			testing.expect_value(t, store.bidi_calls, bidis)
			testing.expect_value(t, len(store.fonts[int(font) - 1].glyphs), glyphs)
		}
	}
	// Invalid heights, empty labels, and explicit-newline rejection.
	for height in ([]f32{-1, math.inf_f32(1), math.nan_f32()}) {
		_, err := fit(&store, Font(1), "label", 24, 2, 0, 100, max_height = height, wrap_at_min = true)
		testing.expect_value(t, err, Error.Invalid_Height)
	}
	_, newline_error := fit(&store, Font(1), "a\nb", 24, 2, 0, 10, max_height = 100, wrap_at_min = true)
	testing.expect_value(t, newline_error, Error.Unsupported_Text)
	empty, empty_error := fit(&store, Font(1), "", 24, 2, 0, 0, max_height = 100, wrap_at_min = true)
	testing.expect_value(t, empty_error, Error.None)
	testing.expect(t, empty.line_count == 1 && empty.width == 0 && !empty.overflow)
	delete(surfaces)
	for &page in store.pages { page.image = {} }
	destroy(&store, nil)
	testing.expect_value(t, len(tracking.allocation_map), 0)
}
