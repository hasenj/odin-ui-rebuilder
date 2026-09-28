package text

import "core:testing"
import "core:mem"
import "core:path/filepath"

// File -> FreeType face -> HarfBuzz shaping -> cached atlas coverage, using
// real variable fonts. Native resources must also survive repeated teardown.
@(test)
latin_font_pipeline :: proc(t: ^testing.T) {
	path, _ := filepath.join({filepath.dir(#location().file_path), "../../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
	defer delete(path)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	for _ in 0..<2 {
		store: Store
		font, err := load(&store, path, "sans")
		if !testing.expect_value(t, err, Error.None) { destroy(&store, nil); return }
		found, ok := find(&store, "sans")
		testing.expect(t, ok && found == font)
		_, err = load(&store, path, "sans")
		testing.expect_value(t, err, Error.Name_Exists)
		_, err = load(&store, "/missing-font.ttf")
		testing.expect_value(t, err, Error.Font_Load_Failed)
		run, shape_error := shape(&store, font, "office", 32, 400)
		testing.expect_value(t, shape_error, Error.None)
		testing.expect(t, len(run.infos) < 6, "The ffi sequence should form a ligature")
		testing.expect(t, run.metrics.width > 50 && run.metrics.ascent > 20 && run.metrics.height > 30)
		glyph_id := run.infos[0].codepoint
		regular, raster_error := cache_glyph(&store, run.font, glyph_id, run.pixel_size, run.weight)
		testing.expect_value(t, raster_error, Error.None)
		testing.expect(t, regular.page >= 0 && regular.size.x > 5 && regular.size.y > 5)
		coverage := false
		for pixel, i in store.pages[0].pixels {
			if i % 4 == 3 && pixel > 0 && pixel < 255 { coverage = true; break }
		}
		testing.expect(t, coverage, "Atlas must contain antialiased glyph coverage")
		cache_count := len(run.font.glyphs)
		warm_allocations := tracking.total_allocation_count
		for _ in 0..<20 {
			run, shape_error = shape(&store, font, "office", 32, 400)
			cached, _ := cache_glyph(&store, run.font, glyph_id, run.pixel_size, run.weight)
			testing.expect_value(t, cached, regular)
		}
		testing.expect_value(t, tracking.total_allocation_count, warm_allocations)
		testing.expect_value(t, len(run.font.glyphs), cache_count)
		run, shape_error = shape(&store, font, "office", 32, 700)
		testing.expect_value(t, shape_error, Error.None)
		bold, bold_error := cache_glyph(&store, run.font, glyph_id, run.pixel_size, run.weight)
		testing.expect_value(t, bold_error, Error.None)
		testing.expect(t, bold.position != regular.position, "Weights need separate cached bitmaps")
		run, shape_error = shape(&store, font, "office", 32, 400)
		again, _ := cache_glyph(&store, run.font, glyph_id, run.pixel_size, run.weight)
		testing.expect_value(t, again, regular)
		plain, _ := measure(&store, font, "café", 24, 1, 400)
		combining, _ := measure(&store, font, "cafe\u0301", 24, 1, 400)
		testing.expect_value(t, combining, plain)
		retina, _ := measure(&store, font, "café", 24, 2, 400)
		testing.expect(t, abs(retina.width - plain.width) < 0.1)
		av, _ := measure(&store, font, "AV", 32, 1, 400)
		a, _ := measure(&store, font, "A", 32, 1, 400)
		v, _ := measure(&store, font, "V", 32, 1, 400)
		testing.expect(t, av.width < a.width + v.width, "Kerning must affect advances")
		empty, empty_error := measure(&store, font, "", 16, 1, 0)
		testing.expect_value(t, empty_error, Error.None)
		testing.expect_value(t, empty.width, f32(0))
		run, _ = shape(&store, font, " ", 16, 0)
		space, _ := cache_glyph(&store, run.font, run.infos[0].codepoint, run.pixel_size, run.weight)
		testing.expect_value(t, space.page, -1)
		_, err = measure(&store, 0, "hi", 16, 1, 0)
		testing.expect_value(t, err, Error.Invalid_Font)
		_, err = measure(&store, font, "hi", 0, 1, 0)
		testing.expect_value(t, err, Error.Invalid_Size)
		_, err = measure(&store, font, "hi", 16, 1, 9999)
		testing.expect_value(t, err, Error.Invalid_Weight)
		_, err = measure(&store, font, "two\nlines", 16, 1, 0)
		testing.expect_value(t, err, Error.Unsupported_Text)
		destroy(&store, nil)
		testing.expect_value(t, len(tracking.allocation_map), 0)
	}
}
