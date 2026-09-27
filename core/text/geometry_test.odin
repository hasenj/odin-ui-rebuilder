package text

import "core:testing"
import "core:mem"
import "core:path/filepath"
import "../primitives"

// Native shaping/rasterization -> prepared geometry -> placed surfaces. Warm
// placement must preserve glyph data while allowing translation, tint, and scale.
@(test)
prepared_geometry_pipeline :: proc(t: ^testing.T) {
	path, _ := filepath.join({filepath.dir(#location().file_path), "../../examples/app5/assets/NotoSansDisplay-VariableFont.ttf"})
	defer delete(path)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	store: Store
	font, err := load(&store, path)
	assert(err == .None)
	value :: "AV office café a\u0308\u0301"
	_, err = measure(&store, font, value, 24, 2, 400)
	assert(err == .None)
	testing.expect_value(t, len(store.pages), 0) // Measuring never prepares bitmaps.
	testing.expect_value(t, store.geometry_builds, u64(0))
	run, _ := shape(&store, font, value, 48, 400)
	quads, prepare_error := prepare_quads(&store, run)
	testing.expect_value(t, prepare_error, Error.None)
	testing.expect(t, len(quads) > 0 && len(quads) < len(run.infos)) // Spaces emit nothing.
	snapshot := make([]Glyph_Quad, len(quads))
	copy(snapshot, quads)
	image := primitives.Image{index = 1, generation = 7}
	original := make([]primitives.Surface, len(quads))
	for quad, i in quads { original[i] = place_quad(quad, image, {10, 20}, {1, 1, 1, 1}, 2) }
	// A different native configuration must not disturb the cached geometry.
	other, _ := shape(&store, font, value, 32, 900)
	_, err = prepare_quads(&store, other)
	assert(err == .None)
	builds, shapes := store.geometry_builds, store.shape_calls
	allocations := tracking.total_allocation_count
	for _ in 0..<100 {
		run, _ = shape(&store, font, value, 48, 400)
		quads, err = prepare_quads(&store, run)
		assert(err == .None)
		testing.expect_value(t, len(quads), len(snapshot))
		for quad, i in quads {
			testing.expect_value(t, quad, snapshot[i])
			moved := place_quad(quad, image, {50, 70}, {0.2, 0.4, 0.6, 0.8}, 2)
			testing.expect_value(t, moved.position, original[i].position + [2]f32{40, 50})
			testing.expect_value(t, moved.size, original[i].size)
			testing.expect_value(t, moved.image_region, original[i].image_region)
			testing.expect_value(t, moved.image, image)
			testing.expect_value(t, moved.background, primitives.Color{0.2, 0.4, 0.6, 0.8})
			// Same physical font size at scale 1 has twice the logical geometry.
			unscaled := place_quad(quad, image, {}, {1, 1, 1, 1}, 1)
			testing.expect_value(t, unscaled.size, original[i].size * 2)
			testing.expect_value(t, unscaled.position, (original[i].position - [2]f32{10, 20}) * 2)
		}
	}
	testing.expect_value(t, store.geometry_builds, builds)
	testing.expect_value(t, store.shape_calls, shapes)
	testing.expect_value(t, tracking.total_allocation_count, allocations)
	testing.expect_value(t, run.font.pixel_size, i32(32 * 64))
	delete(snapshot)
	delete(original)

	// Cache a space-only result too; nil quads alone must not mean "unprepared".
	spaces, _ := shape(&store, font, "   ", 24, 400)
	quads, _ = prepare_quads(&store, spaces)
	testing.expect_value(t, len(quads), 0)
	builds = store.geometry_builds
	_, _ = prepare_quads(&store, spaces)
	testing.expect_value(t, store.geometry_builds, builds)

	// Failed uploads roll back the output, while valid CPU geometry can be reused.
	surfaces: [dynamic]primitives.Surface
	append(&surfaces, primitives.Surface{position = {123, 456}})
	_, draw_error := draw(&store, nil, font, value, 24, 2, 400, {}, {}, &surfaces)
	testing.expect_value(t, draw_error, Error.Upload_Failed)
	testing.expect_value(t, len(surfaces), 1)
	testing.expect_value(t, surfaces[0].position, [2]f32{123, 456})
	delete(surfaces)

	// Preparing an admitted run may require evicting other shaped runs. Keep
	// its own slices valid, account for quad bytes, then verify complete cleanup.
	long_text := make([]u8, 20_000)
	for &ch in long_text { ch = 'a' }
	for i in 0..<5 {
		long_text[0] = 'a' + u8(i)
		_, _ = measure(&store, font, string(long_text), 16, 1, 400)
	}
	run, _ = shape(&store, font, string(long_text), 16, 400)
	count_before := len(store.runs.lookup)
	quads, err = prepare_quads(&store, run)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, len(quads), len(long_text))
	testing.expect(t, len(store.runs.lookup) < count_before)
	testing.expect(t, store.runs.bytes <= MAX_RUN_BYTES)
	accounted_bytes: int
	for &entry in store.runs.entries { accounted_bytes += run_entry_bytes(&entry) }
	testing.expect_value(t, store.runs.bytes, accounted_bytes)
	delete(long_text)

	// Shaping alone fits, but adding quads does not. Use scratch geometry without
	// exceeding the budget or evicting this run while it is being prepared.
	large := make([]u8, MAX_RUN_BYTES / 60)
	for &ch in large { ch = 'a' }
	run, _ = shape(&store, font, string(large), 16, 400)
	assert(run.cache_index != 0)
	bytes_before := store.runs.bytes
	quads, err = prepare_quads(&store, run)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, len(quads), len(large))
	testing.expect(t, !store.runs.entries[run.cache_index - 1].prepared)
	testing.expect_value(t, store.runs.bytes, bytes_before)
	delete(large)
	destroy(&store, nil)
	testing.expect_value(t, len(tracking.allocation_map), 0)
}
