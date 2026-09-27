package text

import "core:testing"
import "core:mem"
import "core:path/filepath"
import "core:encoding/json"

@(private)
Reference_Glyph :: struct {g, cl: u32, dx, dy, ax, ay: i32}

@(test)
arabic_bidi_pipeline :: proc(t: ^testing.T) {
	path, _ := filepath.join({filepath.dir(#location().file_path), "../../examples/app6/assets/Amiri-Regular.ttf"})
	defer delete(path)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	store: Store
	font, load_error := load(&store, path)
	assert(load_error == .None)
	reference: []Reference_Glyph
	assert(json.unmarshal(#load("testdata/arabic-hb.json", []u8), &reference) == nil)
	run, err := shape(&store, font, "السَّلَامُ عَلَيْكُمْ", 32, 0)
	if testing.expect_value(t, err, Error.None) && testing.expect_value(t, len(run.infos), len(reference)) {
		for expected, i in reference {
			testing.expect_value(t, run.infos[i].codepoint, expected.g)
			testing.expect_value(t, run.infos[i].cluster, expected.cl)
			p := run.positions[i]
			// Allow one 26.6 unit for native FreeType version rounding differences.
			testing.expect(t, abs(p.x_advance - expected.ax) <= 1 && abs(p.y_advance - expected.ay) <= 1)
			testing.expect(t, abs(p.x_offset - expected.dx) <= 1 && abs(p.y_offset - expected.dy) <= 1)
		}
	}
	delete(reference)
	_, err = prepare_quads(&store, run)
	testing.expect_value(t, err, Error.None)

	// Direction overrides change visual ordering, not the logical source.
	mixed :: "abc سلام"
	ltr, _ := shape(&store, font, mixed, 32, 0, .LTR)
	testing.expect_value(t, ltr.infos[0].cluster, u32(0))
	rtl, _ := shape(&store, font, mixed, 32, 0, .RTL)
	testing.expect(t, rtl.infos[0].cluster >= 4)
	testing.expect_value(t, rtl.infos[len(rtl.infos) - 1].cluster, u32(2))
	auto, _ := shape(&store, font, mixed, 32, 0)
	testing.expect_value(t, auto.infos[0].cluster, u32(0))
	arabic_first, _ := shape(&store, font, "سلام abc", 32, 0)
	testing.expect_value(t, arabic_first.infos[0].cluster, u32(9))

	// Parentheses are mirrored by HarfBuzz exactly once in an odd-level run.
	paren, _ := shape(&store, font, "(", 32, 0, .LTR)
	left_glyph := paren.infos[0].codepoint
	paren, _ = shape(&store, font, ")", 32, 0, .LTR)
	right_glyph := paren.infos[0].codepoint
	brackets, _ := shape(&store, font, "(سلام)", 32, 0, .RTL)
	testing.expect_value(t, brackets.infos[0].codepoint, left_glyph)
	testing.expect_value(t, brackets.infos[len(brackets.infos) - 1].codepoint, right_glyph)

	// Digits stay LTR inside RTL text; their UTF-8 clusters stay source-relative.
	numbers, _ := shape(&store, font, "سلام 123", 32, 0)
	for i in 0..<3 { testing.expect_value(t, numbers.infos[i].cluster, u32(9 + i)) }
	// Isolates affect ordering but don't emit visible glyphs or missing-glyph errors.
	isolated, isolated_error := shape(&store, font, "abc \u2067سلام 123\u2069 xyz", 32, 0)
	testing.expect_value(t, isolated_error, Error.None)
	isolated_count := len(isolated.infos)
	plain, _ := shape(&store, font, "abc سلام 123 xyz", 32, 0)
	testing.expect_value(t, isolated_count, len(plain.infos))
	// HB may merge a removed control into a neighboring glyph's cluster;
	// absence is verified by glyph count, not by forbidding its byte offset.
	controls, controls_error := shape(&store, font, "\u2067\u2069\u200e", 32, 0)
	testing.expect_value(t, controls_error, Error.None)
	testing.expect_value(t, len(controls.infos), 0)
	// Join controls must affect Arabic shaping even though they have no bitmap.
	joined, _ := shape(&store, font, "بب", 32, 0)
	joined_id := joined.infos[0].codepoint
	separate, _ := shape(&store, font, "ب\u200cب", 32, 0)
	testing.expect(t, separate.infos[0].codepoint != joined_id)

	// Cached line results include base direction and own the language string.
	language := [2]u8{'a', 'r'}
	cached, _ := shape(&store, font, mixed, 32, 0, .RTL, string(language[:]))
	_, _ = prepare_quads(&store, cached)
	language = {'e', 'n'}
	_, _ = shape(&store, font, mixed, 32, 0, .LTR, string(language[:]))
	calls, bidi_calls, builds := store.shape_calls, store.bidi_calls, store.geometry_builds
	allocations := tracking.total_allocation_count
	for _ in 0..<50 {
		cached, _ = shape(&store, font, mixed, 32, 0, .RTL, "ar")
		_, e := prepare_quads(&store, cached)
		assert(e == .None)
		testing.expect(t, cached.infos[0].cluster >= 4)
	}
	testing.expect_value(t, store.shape_calls, calls)
	testing.expect_value(t, store.bidi_calls, bidi_calls)
	testing.expect_value(t, store.geometry_builds, builds)
	testing.expect_value(t, tracking.total_allocation_count, allocations)
	invalid_values := [?]string{"a\nb", "a\u2028b", "a\u2029b", "a\u2029", "a\u0085", "a\t", "\xff"}
	for invalid in invalid_values {
		_, e := shape(&store, font, invalid, 32, 0)
		testing.expect_value(t, e, Error.Unsupported_Text)
	}
	destroy(&store, nil)
	testing.expect_value(t, len(tracking.allocation_map), 0)
}
