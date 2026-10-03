package text

import "core:testing"
import "core:path/filepath"
import "core:mem"

// Exercise fallback through the same shaping, paragraph, atlas and caret paths
// as text(), local layout and edit_text(), including warm-frame work/lifetime.
@(test)
font_fallback_pipeline :: proc(t: ^testing.T) {
	root := filepath.dir(#location().file_path)
	latin_path, _ := filepath.join({root, "../../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
	arabic_path, _ := filepath.join({root, "../../examples/assets/fonts/Amiri-Regular.ttf"})
	defer delete(latin_path); defer delete(arabic_path)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	store: Store
	latin, e1 := load(&store, latin_path, "Latin"); assert(e1 == .None)
	arabic, e2 := load(&store, arabic_path, "Arabic"); assert(e2 == .None)
	family, e3 := font_stack(&store, []Font{latin, arabic}, "Mixed"); assert(e3 == .None)
	_, invalid := font_stack(&store, []Font{0}, "Invalid")
	testing.expect_value(t, invalid, Error.Invalid_Font)

	// A missing glyph must not suppress its neighbours, measurement or editing.
	missing := "before \U0010ffff after"
	for font in ([]Font{latin, family}) {
		for width in ([]f32{-1, 120}) {
			run, err := shape(&store, font, missing, 24, 0, wrap_width = width)
			testing.expect_value(t, err, Error.None)
			tofu, normal: int
			for info in run.infos { if info.codepoint == 0 { tofu += 1 } else { normal += 1 } }
			testing.expect_value(t, tofu, 1)
			testing.expect(t, normal >= 10 && run.metrics.width > 0)
			quads, raster_error := prepare_quads(&store, run)
			testing.expect_value(t, raster_error, Error.None)
			testing.expect(t, len(quads) >= 10)
		}
	}

	value := "office café مرحبا بالعالم 123"
	run, err := shape(&store, family, value, 32, 700)
	testing.expect_value(t, err, Error.None)
	latin_seen, arabic_seen: bool
	for info, i in run.infos {
		testing.expect(t, info.codepoint != 0)
		latin_seen ||= run.sources[i] == latin
		arabic_seen ||= run.sources[i] == arabic
	}
	testing.expect(t, latin_seen && arabic_seen)
	_, raster_error := prepare_quads(&store, run)
	testing.expect_value(t, raster_error, Error.None)
	spans: [dynamic]Caret_Span
	metrics, caret_error := caret_spans(&store, family, value, 32, 1, 700, &spans)
	testing.expect_value(t, caret_error, Error.None)
	testing.expect_value(t, metrics, run.metrics)
	width: f32
	for span in spans { width += abs(span.trailing - span.leading) }
	testing.expect(t, abs(width - metrics.width) < 0.01)
	delete(spans)

	// Loading more faces relocates font records: cached glyph owners are handles.
	for _ in 0..<20 { _, stack_error := font_stack(&store, []Font{family, latin}, ""); assert(stack_error == .None) }
	shapes, coverage, geometry := store.shape_calls, store.coverage_queries, store.geometry_builds
	allocations := tracking.total_allocation_count
	for _ in 0..<30 {
		cached, error := shape(&store, family, value, 32, 700)
		assert(error == .None)
		_, error = prepare_quads(&store, cached); assert(error == .None)
	}
	testing.expect_value(t, store.shape_calls, shapes)
	testing.expect_value(t, store.coverage_queries, coverage)
	testing.expect_value(t, store.geometry_builds, geometry)
	testing.expect_value(t, tracking.total_allocation_count, allocations)

	// The paragraph cache retains font choices along with shaping, so resize
	// does not rescan coverage or re-shape safe word boundaries.
	_, err = shape(&store, family, value, 32, 700, wrap_width = 800); assert(err == .None)
	shapes, coverage = store.shape_calls, store.coverage_queries
	for i in 0..<30 {
		wrapped, error := shape(&store, family, value, 32, 700, wrap_width = 130 + f32(i) * 3)
		assert(error == .None)
		for info in wrapped.infos { testing.expect(t, info.codepoint != 0) }
		_, error = prepare_quads(&store, wrapped); assert(error == .None)
	}
	testing.expect_value(t, store.shape_calls, shapes)
	testing.expect_value(t, store.coverage_queries, coverage)

	when ODIN_OS == .Darwin {
		japanese, error := load(&store, "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc", "Japanese")
		assert(error == .None)
		all, stack_error := font_stack(&store, []Font{family, japanese}, "All"); assert(stack_error == .None)
		mixed, mixed_error := shape(&store, all, "Hello 日本語 مرحبا", 28, 0)
		assert(mixed_error == .None)
		seen := false
		for info, i in mixed.infos { testing.expect(t, info.codepoint != 0); seen ||= mixed.sources[i] == japanese }
		testing.expect(t, seen)
		_, render_error := prepare_quads(&store, mixed); assert(render_error == .None)
	}
	destroy(&store, nil)
	testing.expect_value(t, len(tracking.allocation_map), 0)
}
