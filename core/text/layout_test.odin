package text

import "core:testing"
import "core:mem"
import "core:path/filepath"
import "core:math"
import "core:fmt"
import "../primitives"

// Font files -> wrap/fit -> cached geometry -> placed surfaces. Exercise real
// bidi/shaping, measure/draw agreement, eviction, resizing and complete cleanup.
@(test)
text_layout_pipeline :: proc(t: ^testing.T) {
	root := filepath.dir(#location().file_path)
	latin_path, _ := filepath.join({root, "../../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
	arabic_path, _ := filepath.join({root, "../../examples/assets/fonts/Amiri-Regular.ttf"})
	defer delete(latin_path)
	defer delete(arabic_path)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	store: Store
	font, err := load(&store, latin_path)
	assert(err == .None)
	arabic, e := load(&store, arabic_path)
	assert(e == .None)
	word, _ := measure(&store, font, "office", 24, 2, 400)
	result: Layout
	result, err = layout(&store, font, "office office office", 24, 2, 400, word.width + 0.1)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, result.line_count, 3)
	testing.expect_value(t, result.height, word.height * 3)
	testing.expect_value(t, result.width, word.width)
	testing.expect(t, !result.overflow)
	testing.expect_value(t, len(store.pages), 0) // Measurement never rasterizes.
	run, _ := resolve_layout(&store, result._request)
	testing.expect_value(t, len(run.lines), 3)
	for line, i in run.lines {
		testing.expect_value(t, line.byte_start, i * 7)
		testing.expect_value(t, line.byte_end, i * 7 + 6)
	}
	quads: []Glyph_Quad
	quads, err = prepare_quads(&store, run)
	assert(err == .None)
	count := len(quads) / 3
	testing.expect(t, count > 0 && count < 6) // ffi ligature stays intact.
	for i in 0..<count {
		testing.expect_value(t, quads[count + i].position, quads[i].position + [2]f32{0, word.height * 2})
	}
	// Fake images let the CPU placement path run; native renderer tests cover GPU
	// sampling. Clear them before destruction (these aren't real GPU resources).
	for &page, i in store.pages { page.image = {u32(i + 1), 1} }
	surfaces: [dynamic]primitives.Surface
	err = draw_layout(&store, nil, result, {10, 20}, {200, 300}, {1, 1, 1, 1}, &surfaces, .Center, .Center)
	assert(err == .None)
	origin := [2]f32{10 + (200 - result.width) / 2, 20 + (300 - result.height) / 2}
	testing.expect_value(t, surfaces[0].position, origin + quads[0].position / 2)
	baseline := make([]primitives.Surface, len(surfaces))
	copy(baseline, surfaces[:])
	shapes, bidis, builds := store.shape_calls, store.bidi_calls, store.geometry_builds
	allocations := tracking.total_allocation_count
	for _ in 0..<100 {
		again, _ := layout(&store, font, "office office office", 24, 2, 400, word.width + 0.1)
		clear(&surfaces)
		err = draw_layout(&store, nil, again, {10, 20}, {200, 300}, {1, 1, 1, 1}, &surfaces, .Center, .Center)
		assert(err == .None)
	}
	testing.expect_value(t, store.shape_calls, shapes)
	testing.expect_value(t, store.bidi_calls, bidis)
	testing.expect_value(t, store.geometry_builds, builds)
	testing.expect_value(t, tracking.total_allocation_count, allocations)
	for surface, i in surfaces { testing.expect_value(t, surface, baseline[i]) }

	// Hard/empty lines, trimmed edge spaces, NBSP, and long-word overflow.
	for value in ([]string{"a\n\nb\n", "a\r\n\r\nb\r\n", "a\u2028\u2028b\u2028", "a\u2029\u2029b\u2029", "a\u0085\u0085b\u0085"}) {
		hard, error := layout(&store, font, value, 24, 2, 400, 200)
		testing.expect_value(t, error, Error.None)
		testing.expect_value(t, hard.line_count, 4)
		testing.expect_value(t, hard.height, word.height * 4)
	}
	empty, _ := layout(&store, font, "", 24, 2, 400, 0)
	testing.expect_value(t, empty.line_count, 1)
	testing.expect_value(t, empty.width, f32(0))
	testing.expect(t, !empty.overflow)
	spaces, _ := layout(&store, font, "   office   office   ", 24, 2, 400, word.width + 0.1)
	testing.expect_value(t, spaces.line_count, 2)
	nbsp, _ := layout(&store, font, "office\u00a0office", 24, 2, 400, word.width)
	testing.expect(t, nbsp.overflow && nbsp.line_count == 1)
	zero, _ := layout(&store, font, "office office", 24, 2, 400, 0)
	testing.expect(t, zero.overflow && zero.line_count == 2)

	// A wrapped continuation inherits paragraph direction even though its first
	// strong letter is Latin. Compare with a separately forced-RTL reference.
	mixed :: "مرحبابكمالجميع Hello 123!"
	latin, _ := measure(&store, arabic, "Hello 123!", 32, 1, 0, .RTL)
	bidi, bidi_error := layout(&store, arabic, mixed, 32, 1, 0, latin.width + 0.1)
	testing.expect_value(t, bidi_error, Error.None)
	run, _ = resolve_layout(&store, bidi._request)
	testing.expect_value(t, len(run.lines), 2)
	last := run.lines[len(run.lines) - 1]
	snapshot := make([]u32, last.end - last.start)
	clusters := make([]u32, len(snapshot))
	for info, i in run.infos[last.start:last.end] { snapshot[i], clusters[i] = info.codepoint, info.cluster }
	reference, _ := shape(&store, arabic, "Hello 123!", 32, 0, .RTL)
	testing.expect_value(t, len(snapshot), len(reference.infos))
	for info, i in reference.infos {
		testing.expect_value(t, snapshot[i], info.codepoint)
		testing.expect_value(t, clusters[i], info.cluster + u32(last.byte_start))
	}
	delete(snapshot)
	delete(clusters)
	// Arabic words are reshaped on each line, retaining marks and source clusters.
	arabic_word :: "السَّلَامُ"
	arabic_width, _ := measure(&store, arabic, arabic_word, 32, 1, 0)
	joined, _ := layout(&store, arabic, "السَّلَامُ السَّلَامُ", 32, 1, 0, arabic_width.width + 0.1)
	run, _ = resolve_layout(&store, joined._request)
	testing.expect_value(t, len(run.lines), 2)
	first, second := run.lines[0], run.lines[1]
	testing.expect_value(t, first.end - first.start, second.end - second.start)
	for info, i in run.infos[first.start:first.end] {
		testing.expect_value(t, info.codepoint, run.infos[second.start + i].codepoint)
		testing.expect_value(t, run.positions[first.start + i], run.positions[second.start + i])
	}

	// Unequal line widths align independently; blank lines advance the baseline.
	unequal, _ := layout(&store, font, "office a\n\noffice", 24, 2, 400, 1000)
	run, _ = resolve_layout(&store, unequal._request)
	quads, _ = prepare_quads(&store, run)
	for &page, i in store.pages { page.image = {u32(i + 1), 1} }
	for align in ([]Align{.Start, .Center, .End}) {
		clear(&surfaces)
		err = draw_layout(&store, nil, unequal, {5, 7}, {300, 400}, {1, 1, 1, 1}, &surfaces, align, .End)
		assert(err == .None)
		for quad, i in quads {
			extra := 300 - run.lines[quad.line].width / 2
			dx: f32
			switch align {
			case .Start:
			case .Center: dx = extra / 2
			case .End: dx = extra
			}
			testing.expect_value(t, surfaces[i].position, [2]f32{5 + dx, 7 + 400 - unequal.height} + quad.position / 2)
		}
	}
	// Greedy wrapping fills each line whenever the next whole word fits.
	phrase := "office a office a office a office a office a office a office a"
	limit, _ := measure(&store, font, "office a office", 24, 2, 400)
	greedy, _ := layout(&store, font, phrase, 24, 2, 400, limit.width + 0.1)
	run, _ = resolve_layout(&store, greedy._request)
	for line, i in run.lines {
		testing.expect(t, line.width / 2 <= limit.width + 0.1)
		if i + 1 < len(run.lines) {
			next_word_end := run.lines[i + 1].byte_start
			for next_word_end < len(phrase) && phrase[next_word_end] != ' ' { next_word_end += 1 }
			candidate, _ := measure(&store, font, phrase[line.byte_start:next_word_end], 24, 2, 400)
			testing.expect(t, candidate.width > limit.width + 0.1)
		}
	}

	// Fit uses one desired-size cached shape/geometry at every destination width.
	full, _ := fit(&store, font, "Save all changes", 24, 2, 400, 1000)
	run, _ = resolve_layout(&store, full._request)
	quads, _ = prepare_quads(&store, run)
	first_quad := quads[0]
	reserve(&surfaces, len(quads))
	for &page, i in store.pages { page.image = {u32(i + 1), 1} }
	shapes, bidis, builds = store.shape_calls, store.bidi_calls, store.geometry_builds
	allocations = tracking.total_allocation_count
	for i in 0..<100 {
		fraction := 0.25 + f32(i) / 100
		fitted, error := fit(&store, font, "Save all changes", 24, 2, 400, full.width * fraction)
		assert(error == .None)
		factor := clamp(fraction, 0.5, 1)
		testing.expect(t, math.abs(fitted.size - 24 * factor) < 0.001)
		testing.expect(t, math.abs(fitted.height - full.height * factor) < 0.001)
		testing.expect_value(t, fitted.overflow, fraction < 0.5)
		clear(&surfaces)
		err = draw_layout(&store, nil, fitted, {5, 7}, {full.width * fraction, 70}, {1, 1, 1, 1}, &surfaces, .Center, .Center)
		assert(err == .None)
		testing.expect(t, math.abs(surfaces[0].size.x - first_quad.size.x / 2 * factor) < 0.001)
	}
	testing.expect_value(t, store.shape_calls, shapes)
	testing.expect_value(t, store.bidi_calls, bidis)
	testing.expect_value(t, store.geometry_builds, builds)
	testing.expect_value(t, tracking.total_allocation_count, allocations)

	// Cached data owns caller text; a result borrows it. Reacquire using fresh
	// storage after mutation. A previously measured literal survives eviction.
	buffer: [64]u8
	value := fmt.bprintf(buffer[:], "office office office")
	_, _ = layout(&store, font, value, 24, 2, 400, word.width + 0.1)
	for &ch in buffer { ch = 'X' }
	for i in 0..<MAX_RUNS + 1 {
		value = fmt.bprintf(buffer[:], "eviction %d", i)
		_, _ = measure(&store, font, value, 16, 1, 400)
	}
	clear(&surfaces)
	err = draw_layout(&store, nil, result, {10, 20}, {200, 300}, {1, 1, 1, 1}, &surfaces, .Center, .Center)
	testing.expect_value(t, err, Error.None)
	for surface, i in surfaces { testing.expect_value(t, surface, baseline[i]) }
	testing.expect(t, store.runs.bytes <= MAX_RUN_BYTES)
	bytes: int
	for &entry in store.runs.entries { bytes += run_entry_bytes(&entry) }
	testing.expect_value(t, store.runs.bytes, bytes)

	_, err = layout(&store, font, "a", 24, 2, 400, -1)
	testing.expect_value(t, err, Error.Invalid_Width)
	_, err = layout(&store, font, "a\tb", 24, 2, 400, 100)
	testing.expect_value(t, err, Error.Unsupported_Text)
	_, err = fit(&store, font, "a\nb", 24, 2, 400, 100)
	testing.expect_value(t, err, Error.Unsupported_Text)
	_, err = fit(&store, font, "a", 24, 2, 400, 100, 0)
	testing.expect_value(t, err, Error.Invalid_Scale)
	_, err = layout(&store, font, "a", 24, 1, 400, f32(max(i32) / 64))
	testing.expect_value(t, err, Error.Invalid_Width) // f32 rounds this up to 2^25.
	_, err = layout(&store, font, "a", 24, 2, 400, math.inf_f32(1))
	testing.expect_value(t, err, Error.Invalid_Width)
	_, err = fit(&store, font, "a", 24, 2, 400, math.nan_f32())
	testing.expect_value(t, err, Error.Invalid_Width)
	delete(surfaces)
	delete(baseline)
	for &page in store.pages { page.image = {} }
	destroy(&store, nil)
	testing.expect_value(t, len(tracking.allocation_map), 0)
}
