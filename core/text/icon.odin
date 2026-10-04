package text

import "native"
import c "core:c"
import "core:math"
import "../../platform"
import "../primitives"

// A glyph index in one physical font, valid for that font/window's lifetime.
// Code points/names belong to icon packages; core is independent of any set.
Icon_Glyph :: struct {font: Font, glyph: u32}

resolve_icon :: proc(store: ^Store, font: Font, codepoint: rune) -> (Icon_Glyph, Error) {
	if font == 0 || int(font) > len(store.fonts) { return {}, .Invalid_Font }
	face := store.fonts[int(font)-1].face
	if face == nil { return {}, .Invalid_Font } // Font stacks cannot name raw glyphs.
	id := native.FT_Get_Char_Index(face, c.ulong(codepoint))
	if id == 0 { return {}, .Missing_Glyph }
	return {font, u32(id)}, .None
}

// Centers ink bounds, retaining aspect ratio. Glyphs use the existing grayscale
// atlas; no shaping, bidi, or per-frame file reads. Each warm draw emits one quad.
draw_icon :: proc(store: ^Store, renderer: platform.Renderer, icon: Icon_Glyph, position, bounds: [2]f32, scale: f32, color: primitives.Color, surfaces: ^[dynamic]primitives.Surface) -> Error {
	if icon == (Icon_Glyph{}) { return .None }
	if icon.font == 0 || int(icon.font) > len(store.fonts) { return .Invalid_Font }
	font := &store.fonts[int(icon.font)-1]
	if font.face == nil || int(icon.glyph) >= int(font.face.num_glyphs) { return .Invalid_Font }
	if !(scale > 0 && scale <= 16) { return .Invalid_Scale }
	if bounds.x <= 0 || bounds.y <= 0 { return .None }
	if !(bounds.x <= max(f32) && bounds.y <= max(f32)) { return .Invalid_Size }
	extent, found := font.icon_metrics[icon.glyph]
	if !found {
		// A shared variable face may have last been used at a different weight.
		// Icon_Glyph selects the face's defaults; measure and rasterize alike.
		if err := configure_font(font, 16*64, source_weight(font, 0)); err != .None { return err }
		// FT_LOAD_NO_SCALE exposes the outline extent in font units.
		if native.FT_Load_Glyph(font.face, icon.glyph, 1 | native.FT_LOAD_NO_HINTING | native.FT_LOAD_NO_BITMAP) != 0 { return .Rasterization_Failed }
		extent = {f32(font.face.glyph.metrics[0]), f32(font.face.glyph.metrics[1])}
		font.icon_metrics[icon.glyph] = extent
	}
	if extent.x <= 0 || extent.y <= 0 { return .None }
	em := min(bounds.x/extent.x, bounds.y/extent.y) * f32(font.face.units_per_em) * scale
	if !(em > 0 && em < 32768) { return .Invalid_Size }
	glyph, err := cache_glyph(store, font, icon.glyph, max(1, i32(math.round(em*64))), source_weight(font, 0))
	if err != .None || glyph.page < 0 { return err }
	page := &store.pages[glyph.page]
	if page.image == (primitives.Image{}) {
		img, image_err := platform.create_image(renderer, page.pixels, {ATLAS_SIZE, ATLAS_SIZE})
		if image_err != .None { return .Upload_Failed }
		page.image = img; page.dirty = false
	}
	// Account for transparent atlas padding without enlarging the actual ink.
	ink := [2]f32{f32(glyph.size.x-2), f32(glyph.size.y-2)} / scale
	factor := min(1, min(bounds.x/ink.x, bounds.y/ink.y))
	size := [2]f32{f32(glyph.size.x), f32(glyph.size.y)} * (factor/scale)
	append(surfaces, primitives.Surface{position = position+(bounds-size)/2, size = size, background = color, image = page.image,
		image_region = {f32(glyph.position.x)/ATLAS_SIZE, f32(glyph.position.y)/ATLAS_SIZE,
			f32(glyph.position.x+glyph.size.x)/ATLAS_SIZE, f32(glyph.position.y+glyph.size.y)/ATLAS_SIZE}})
	return .None
}
