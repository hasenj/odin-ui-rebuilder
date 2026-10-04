package text

import "core:testing"
import "core:mem"

// Real embedded font -> owned memory face -> codepoint lookup -> raster cache.
// No platform-native font or shaping is used to draw icons.
@(test)
icon_font_pipeline :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	store: Store
	source := #load("../../icons/default/icons.ttf", []u8)
	bytes := make([]u8, len(source)); copy(bytes, source)
	font, err := load_bytes(&store, bytes, "icons")
	for &byte in bytes { byte = 0 }; delete(bytes)
	testing.expect_value(t, err, Error.None)
	_, err = load_bytes(&store, source, "icons")
	testing.expect_value(t, err, Error.Name_Exists)
	_, err = load_bytes(&store, []u8{1, 2, 3})
	testing.expect_value(t, err, Error.Font_Load_Failed)
	for codepoint in rune(0xe000)..=rune(0xe009) {
		icon, resolve_err := resolve_icon(&store, font, codepoint)
		testing.expect_value(t, resolve_err, Error.None)
		testing.expect(t, icon.glyph > 0 && icon.font == font)
		for pixels in ([2]i32{16, 32}) {
			glyph, raster_err := cache_glyph(&store, &store.fonts[int(font)-1], icon.glyph, pixels*64, 0)
			testing.expect_value(t, raster_err, Error.None)
			testing.expect(t, glyph.page >= 0)
			if glyph.page < 0 { continue }
			partial := 0
			for y in 0..<glyph.size.y {
				for x in 0..<glyph.size.x {
					a := store.pages[glyph.page].pixels[((glyph.position.y+y)*ATLAS_SIZE+glyph.position.x+x)*4+3]
					if a > 0 && a < 255 { partial += 1 }
				}
			}
			testing.expect(t, partial > 0, "Each icon must contain antialiased coverage")
			allocations := tracking.total_allocation_count
			cached, _ := cache_glyph(&store, &store.fonts[int(font)-1], icon.glyph, pixels*64, 0)
			testing.expect_value(t, cached, glyph)
			testing.expect_value(t, tracking.total_allocation_count, allocations)
		}
	}
	_, err = resolve_icon(&store, font, 'A'); testing.expect_value(t, err, Error.Missing_Glyph)
	stack, _ := font_stack(&store, []Font{font}, "stack")
	_, err = resolve_icon(&store, stack, '\ue000'); testing.expect_value(t, err, Error.Invalid_Font)
	_, err = resolve_icon(&store, Font(999), '\ue000'); testing.expect_value(t, err, Error.Invalid_Font)
	testing.expect_value(t, store.shape_calls, u64(0))
	destroy(&store, nil)
	testing.expect_value(t, len(tracking.allocation_map), 0)
}
