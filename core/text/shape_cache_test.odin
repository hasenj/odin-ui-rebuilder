package text

import "core:testing"
import "core:mem"
import "core:path/filepath"
import "core:fmt"

// Exercise actual fonts and HB buffers: cache hits must survive other shaping,
// native face changes, caller buffer reuse, font-table growth, and LRU eviction.
@(test)
shaped_run_cache_pipeline :: proc(t: ^testing.T) {
	path, _ := filepath.join({filepath.dir(#location().file_path), "../../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
	defer delete(path)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	store: Store
	font, err := load(&store, path, "body")
	assert(err == .None)
	regular, _ := measure(&store, font, "office", 32, 1, 400)
	bold, _ := measure(&store, font, "office", 32, 1, 900)
	small, _ := measure(&store, font, "office", 12, 1, 400)
	calls := store.shape_calls
	allocations := tracking.total_allocation_count
	for _ in 0..<100 {
		actual, e := measure(&store, font, "office", 32, 1, 0) // Default is 400.
		assert(e == .None)
		testing.expect_value(t, actual, regular)
		actual, _ = measure(&store, font, "office", 32, 1, 900)
		testing.expect_value(t, actual, bold)
		actual, _ = measure(&store, font, "office", 12, 1, 400)
		testing.expect_value(t, actual, small)
		// Equivalent physical size reuses the run, but logical metrics differ.
		actual, _ = measure(&store, font, "office", 16, 2, 400)
		testing.expect_value(t, actual, logical_metrics(regular, 2))
	}
	testing.expect_value(t, store.shape_calls, calls)
	testing.expect_value(t, tracking.total_allocation_count, allocations)

	// Measure at one size, switch the native face, then draw the cached run:
	// rasterization must restore the requested size/weight on a bitmap miss.
	expected, _ := shape(&store, font, "Q", 24, 400)
	expected_metrics := expected.metrics
	_, _ = shape(&store, font, "X", 64, 900)
	calls = store.shape_calls
	run, _ := shape(&store, font, "Q", 24, 400)
	testing.expect_value(t, store.shape_calls, calls)
	testing.expect_value(t, run.font.pixel_size, i32(64 * 64))
	glyph, raster_error := cache_glyph(&store, run.font, run.infos[0].codepoint, run.pixel_size, run.weight)
	testing.expect_value(t, raster_error, Error.None)
	testing.expect_value(t, run.font.pixel_size, i32(24 * 64))
	testing.expect_value(t, run.font.weight, run.weight)
	testing.expect_value(t, run.metrics, expected_metrics)
	testing.expect(t, glyph.size.x < 32 && glyph.size.y < 32)

	// Incoming string storage can change immediately after the call.
	buffer: [64]u8
	value := fmt.bprintf(buffer[:], "temporary %d", 17)
	owned, _ := measure(&store, font, value, 16, 1, 400)
	for &b in buffer { b = 'Z' }
	_, _ = measure(&store, font, string(buffer[:12]), 16, 1, 400)
	calls = store.shape_calls
	actual, _ := measure(&store, font, "temporary 17", 16, 1, 400)
	testing.expect_value(t, actual, owned)
	testing.expect_value(t, store.shape_calls, calls)

	// Cached runs identify fonts by handle, not a pointer into the growing array.
	for i in 0..<20 {
		alias := fmt.bprintf(buffer[:], "font-%d", i)
		other, load_error := load(&store, path, alias)
		assert(load_error == .None)
		_, _ = measure(&store, other, "office", 32, 1, 400)
	}
	calls = store.shape_calls
	run, _ = shape(&store, font, "office", 32, 400)
	testing.expect_value(t, store.shape_calls, calls)
	testing.expect(t, run.font == &store.fonts[0])
	testing.expect_value(t, run.metrics, regular)

	// Dynamic labels cannot grow the cache forever. Keep a hot run alive while
	// inserting more than the entry limit; the oldest unused run is evicted.
	_, _ = measure(&store, font, "old unused run", 16, 1, 400)
	for i in 0..<MAX_RUNS + 10 {
		label := fmt.bprintf(buffer[:], "dynamic label %d", i)
		_, _ = measure(&store, font, label, 16, 1, 400)
		calls = store.shape_calls
		_, _ = measure(&store, font, "office", 32, 1, 400)
		testing.expect_value(t, store.shape_calls, calls)
	}
	testing.expect_value(t, len(store.runs.lookup), MAX_RUNS)
	testing.expect(t, len(store.runs.entries) <= MAX_RUNS && store.runs.bytes <= MAX_RUN_BYTES)
	calls = store.shape_calls
	_, _ = measure(&store, font, "old unused run", 16, 1, 400)
	testing.expect_value(t, store.shape_calls, calls + 1)

	// A few long strings exercise the byte budget independently of entry count.
	long_text := make([]u8, 20_000)
	for &b in long_text { b = 'a' }
	for i in 0..<8 {
		long_text[0] = 'a' + u8(i)
		_, e := measure(&store, font, string(long_text), 16, 1, 400)
		testing.expect_value(t, e, Error.None)
		testing.expect(t, store.runs.bytes <= MAX_RUN_BYTES)
	}
	delete(long_text)
	testing.expect(t, len(store.runs.lookup) < MAX_RUNS)
	// An individual oversized run bypasses caching rather than evicting all runs.
	huge := make([]u8, MAX_RUN_BYTES / 40 + 1)
	for &b in huge { b = 'a' }
	count_before := len(store.runs.lookup)
	bytes_before := store.runs.bytes
	_, huge_error := measure(&store, font, string(huge), 16, 1, 400)
	testing.expect_value(t, huge_error, Error.None)
	testing.expect_value(t, len(store.runs.lookup), count_before)
	testing.expect_value(t, store.runs.bytes, bytes_before)
	delete(huge)
	destroy(&store, nil)
	testing.expect_value(t, len(tracking.allocation_map), 0)
}
