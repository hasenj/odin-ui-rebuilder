// Single-line Latin shaping and cached grayscale glyphs. Geometry uses physical
// pixels internally; the UI wrapper converts to/from logical window points.
package text

import "native"
import c "core:c"
import "core:math"
import "core:strings"
import "../../platform"
import "../primitives"

// O(1) handle into a window-owned append-only font table. No slot reuse/unload in
// this stage: handles stay valid until the window closes, regardless of resizing.
Font :: distinct u32
Error :: enum {
	None, Font_Load_Failed, Invalid_Font, Name_Exists, Invalid_Size,
	Invalid_Weight, Unsupported_Weight, Unsupported_Text, Missing_Glyph,
	Shaping_Failed, Rasterization_Failed, Atlas_Full, Upload_Failed,
}
Metrics :: struct {width, height, ascent, descent: f32}

Store :: struct {
	library: native.FT_Library,
	buffer: native.HB_Buffer,
	fonts: [dynamic]Font_Record,
	names: map[string]Font,
	pages: [dynamic]Page,
	upload: [dynamic]u8,
	runs: Run_Cache,
	shape_calls, shape_cache_hits: u64,
}

@(private)
Font_Record :: struct {
	face: ^native.FT_Face,
	hb: native.HB_Font,
	name: string,
	axes: ^native.FT_MM_Var,
	coords: []c.long,
	weight_axis: int,
	pixel_size: i32,
	weight: c.long,
	glyphs: map[Glyph_Key]Glyph,
}
@(private)
Glyph_Key :: struct {id: u32, pixel_size: i32, weight: c.long}
@(private)
Glyph :: struct {page: int, position, size: [2]int, bearing: [2]f32}
@(private)
Page :: struct {
	image: primitives.Image,
	pixels: []u8,
	x, y, row_height: int,
	dirty: bool,
	dirty_min, dirty_max: [2]int,
}
@(private)
ATLAS_SIZE :: 1024
@(private)
MAX_PAGES :: 16 // Bounded at 64 MiB CPU + 64 MiB GPU; no eviction yet.

load :: proc(store: ^Store, path: string, name: string = "", face_index: int = 0) -> (Font, Error) {
	if store.library == nil {
		if native.FT_Init_FreeType(&store.library) != 0 {
			return 0, .Font_Load_Failed
		}
		store.buffer = native.hb_buffer_create()
	}
	face: ^native.FT_Face
	path_z := strings.clone_to_cstring(path)
	defer delete(path_z)
	if face_index < 0 || native.FT_New_Face(store.library, path_z, c.long(face_index), &face) != 0 {
		return 0, .Font_Load_Failed
	}
	keep := false
	defer { if !keep { native.FT_Done_Face(face) } }
	// Scalable outlines and Unicode charmap are required by this initial path.
	if face.units_per_em == 0 || native.FT_Select_Charmap(face, 0x756e6963) != 0 { // 'unic'
		return 0, .Font_Load_Failed
	}
	alias := name
	if alias == "" {
		alias = string(face.family_name)
	}
	if alias == "" {
		alias = path
	}
	if _, exists := store.names[alias]; exists {
		return 0, .Name_Exists
	}
	if native.FT_Set_Char_Size(face, 0, 16 * 64, 72, 72) != 0 {
		return 0, .Font_Load_Failed
	}
	record := Font_Record{face = face, weight_axis = -1}
	if face.face_flags & native.FT_FACE_FLAG_MULTIPLE_MASTERS != 0 {
		if native.FT_Get_MM_Var(face, &record.axes) != 0 {
			return 0, .Font_Load_Failed
		}
		record.coords = make([]c.long, int(record.axes.num_axis))
		for axis, i in record.axes.axis[:record.axes.num_axis] {
			record.coords[i] = axis.def
			if axis.tag == 0x77676874 { // 'wght'
				record.weight_axis = i
			}
		}
	}
	record.name = strings.clone(alias)
	record.hb = native.hb_ft_font_create_referenced(face)
	native.hb_ft_font_set_load_flags(record.hb, native.FT_LOAD_NO_HINTING | native.FT_LOAD_NO_BITMAP)
	append(&store.fonts, record)
	handle := Font(len(store.fonts))
	store.names[record.name] = handle
	keep = true
	return handle, .None
}

find :: proc(store: ^Store, name: string) -> (Font, bool) {
	font, ok := store.names[name]
	return font, ok
}

// All fonts, glyph caches, atlas pages, and native objects belong to the window.
destroy :: proc(store: ^Store, renderer: platform.Renderer) {
	destroy_run_cache(&store.runs)
	for &font in store.fonts {
		native.hb_font_destroy(font.hb)
		if font.axes != nil {
			native.FT_Done_MM_Var(store.library, font.axes)
		}
		delete(font.coords)
		delete(font.glyphs)
		delete(font.name)
		native.FT_Done_Face(font.face)
	}
	for page in store.pages {
		platform.destroy_image(renderer, page.image)
		delete(page.pixels)
	}
	delete(store.fonts)
	delete(store.names)
	delete(store.pages)
	delete(store.upload)
	if store.buffer != nil { native.hb_buffer_destroy(store.buffer) }
	if store.library != nil { native.FT_Done_FreeType(store.library) }
	store^ = {}
}

@(private)
Shape :: struct {
	font: ^Font_Record,
	infos: []native.HB_Glyph_Info,
	positions: []native.HB_Glyph_Position,
	metrics: Metrics,
	pixel_size: i32,
	weight: c.long,
}

// Returned glyph slices are borrowed until the next shape call. Cache hits
// avoid HarfBuzz and leave the current native font size/weight untouched.
@(private)
shape :: proc(store: ^Store, handle: Font, value: string, pixel_size, weight: f32) -> (Shape, Error) {
	if handle == 0 || int(handle) > len(store.fonts) { return {}, .Invalid_Font }
	if !(pixel_size > 0 && pixel_size <= 2048) { return {}, .Invalid_Size }
	if !(weight >= 0 && weight <= 32767) { return {}, .Invalid_Weight }
	if len(value) > int(max(i32)) { return {}, .Unsupported_Text }
	font := &store.fonts[int(handle) - 1]
	px := max(i32(math.round(pixel_size * 64)), 1)
	w: c.long
	if font.weight_axis >= 0 {
		axis := font.axes.axis[font.weight_axis]
		w = axis.def if weight == 0 else c.long(math.round(weight * 65536))
		if w < axis.minimum || w > axis.maximum { return {}, .Invalid_Weight }
	} else if weight != 0 {
		return {}, .Unsupported_Weight
	}
	key := Run_Key{handle, px, w, value}
	if cached, ok := lookup_run(&store.runs, key, font); ok {
		store.shape_cache_hits += 1
		return cached, .None
	}
	for ch in value {
		if ch == '\n' || ch == '\r' || ch == '\t' { return {}, .Unsupported_Text }
	}
	if err := configure_font(font, px, w); err != .None { return {}, err }
	buffer := store.buffer
	native.hb_buffer_clear_contents(buffer)
	native.hb_buffer_add_utf8(buffer, raw_data(value), c.int(len(value)), 0, c.int(len(value)))
	native.hb_buffer_set_direction(buffer, 4) // HB_DIRECTION_LTR
	native.hb_buffer_set_script(buffer, 0x4c61746e) // 'Latn'
	native.hb_buffer_set_language(buffer, native.hb_language_from_string("en", -1))
	store.shape_calls += 1
	native.hb_shape(font.hb, buffer, nil, 0)
	if native.hb_buffer_allocation_successful(buffer) == 0 { return {}, .Shaping_Failed }
	count := native.hb_buffer_get_length(buffer)
	infos := native.hb_buffer_get_glyph_infos(buffer, nil)[:count]
	positions := native.hb_buffer_get_glyph_positions(buffer, nil)[:count]
	advance: f32
	for info, i in infos {
		if info.codepoint == 0 { return {}, .Missing_Glyph }
		advance += f32(positions[i].x_advance) / 64
	}
	m := font.face.size.metrics
	metrics := Metrics{width = advance, height = f32(m.height) / 64, ascent = f32(m.ascender) / 64, descent = -f32(m.descender) / 64}
	run := Shape{font, infos, positions, metrics, px, w}
	return store_run(&store.runs, key, run), .None
}

measure :: proc(store: ^Store, font: Font, value: string, size, scale, weight: f32) -> (Metrics, Error) {
	if !(scale > 0 && scale <= 16) { return {}, .Invalid_Size }
	run, err := shape(store, font, value, size * scale, weight)
	return logical_metrics(run.metrics, scale), err
}

// Measurement and drawing share shaped runs. Warm text avoids shaping, native
// font reconfiguration, rasterization, uploads, and allocation.
draw :: proc(store: ^Store, renderer: platform.Renderer, font: Font, value: string, size, scale, weight: f32,
	position: [2]f32, color: primitives.Color, surfaces: ^[dynamic]primitives.Surface) -> (Metrics, Error) {
	if !(scale > 0 && scale <= 16) { return {}, .Invalid_Size }
	run, err := shape(store, font, value, size * scale, weight)
	if err != .None { return {}, err }
	start := len(surfaces^)
	// Failure must not leave partially emitted text in the frame.
	succeeded := false
	defer { if !succeeded { resize(surfaces, start) } }
	pen: [2]f32
	for info, i in run.infos {
		glyph, glyph_error := cache_glyph(store, run.font, info.codepoint, run.pixel_size, run.weight)
		if glyph_error != .None { return {}, glyph_error }
		p := run.positions[i]
		if glyph.page >= 0 {
			page := &store.pages[glyph.page]
			if page.image == (primitives.Image{}) {
				image, image_error := platform.create_image(renderer, page.pixels, {ATLAS_SIZE, ATLAS_SIZE})
				if image_error != .None { return {}, .Upload_Failed }
				page.image = image
				page.dirty = false
			}
			offset := [2]f32{f32(p.x_offset) / 64, -f32(p.y_offset) / 64}
			append(surfaces, primitives.Surface{
				position = position + (pen + offset + glyph.bearing + [2]f32{0, run.metrics.ascent}) / scale,
				size = [2]f32{f32(glyph.size.x), f32(glyph.size.y)} / scale,
				background = color, image = page.image,
				image_region = {f32(glyph.position.x) / ATLAS_SIZE, f32(glyph.position.y) / ATLAS_SIZE,
					f32(glyph.position.x + glyph.size.x) / ATLAS_SIZE, f32(glyph.position.y + glyph.size.y) / ATLAS_SIZE},
			})
		}
		pen += [2]f32{f32(p.x_advance), -f32(p.y_advance)} / 64
	}
	succeeded = true
	return logical_metrics(run.metrics, scale), .None
}

@(private)
logical_metrics :: proc(m: Metrics, scale: f32) -> Metrics {
	return {m.width / scale, m.height / scale, m.ascent / scale, m.descent / scale}
}

@(private)
cache_glyph :: proc(store: ^Store, font: ^Font_Record, id: u32, pixel_size: i32, weight: c.long) -> (Glyph, Error) {
	key := Glyph_Key{id, pixel_size, weight}
	if cached, ok := font.glyphs[key]; ok { return cached, .None }
	// A cached shape may refer to a different size/weight than the last native
	// operation. Restore it only if a bitmap actually needs rasterization.
	if err := configure_font(font, pixel_size, weight); err != .None { return {}, err }
	if native.FT_Load_Glyph(font.face, id, native.FT_LOAD_NO_HINTING | native.FT_LOAD_NO_BITMAP) != 0 ||
	   native.FT_Render_Glyph(font.face.glyph, 0) != 0 { return {}, .Rasterization_Failed }
	slot := font.face.glyph
	bitmap := slot.bitmap
	glyph := Glyph{page = -1}
	if bitmap.width == 0 || bitmap.rows == 0 {
		font.glyphs[key] = glyph
		return glyph, .None
	}
	if bitmap.pixel_mode != native.FT_PIXEL_MODE_GRAY { return {}, .Rasterization_Failed }
	// One transparent texel on every edge avoids atlas bleeding and keeps the
	// surface's rectangle edge antialiasing outside the glyph coverage itself.
	w, h := int(bitmap.width) + 2, int(bitmap.rows) + 2
	if w > ATLAS_SIZE || h > ATLAS_SIZE { return {}, .Atlas_Full }
	page_index := len(store.pages) - 1
	if page_index >= 0 {
		page := &store.pages[page_index]
		if page.x + w > ATLAS_SIZE {
			page.x = 0
			page.y += page.row_height
			page.row_height = 0
		}
		if page.y + h > ATLAS_SIZE { page_index = -1 }
	}
	if page_index < 0 {
		if len(store.pages) >= MAX_PAGES { return {}, .Atlas_Full }
		append(&store.pages, Page{pixels = make([]u8, ATLAS_SIZE * ATLAS_SIZE * 4)})
		page_index = len(store.pages) - 1
	}
	page := &store.pages[page_index]
	glyph = {page = page_index, position = {page.x, page.y}, size = {w, h},
		bearing = {f32(slot.bitmap_left) - 1, -f32(slot.bitmap_top) - 1}}
	for y in 0..<int(bitmap.rows) {
		row := y * int(bitmap.pitch)
		for x in 0..<int(bitmap.width) {
			a := bitmap.buffer[row + x]
			dst := ((page.y + y + 1) * ATLAS_SIZE + page.x + x + 1) * 4
			// Premultiplied white coverage, ready for the existing image renderer.
			for channel in 0..<4 { page.pixels[dst + channel] = a }
		}
	}
	if !page.dirty {
		page.dirty_min, page.dirty_max = glyph.position, glyph.position + glyph.size
	} else {
		page.dirty_min = {min(page.dirty_min.x, page.x), min(page.dirty_min.y, page.y)}
		page.dirty_max = {max(page.dirty_max.x, page.x + w), max(page.dirty_max.y, page.y + h)}
	}
	page.dirty = true
	page.x += w
	page.row_height = max(page.row_height, h)
	font.glyphs[key] = glyph
	return glyph, .None
}

// Batch all missing glyph uploads for a page into one dirty-region update.
// Called after UI update and before the frame is submitted to the renderer.
flush :: proc(store: ^Store, renderer: platform.Renderer) -> Error {
	for &page in store.pages {
		if !page.dirty || page.image == (primitives.Image{}) { continue }
		size := page.dirty_max - page.dirty_min
		resize(&store.upload, size.x * size.y * 4)
		for y in 0..<size.y {
			src := ((page.dirty_min.y + y) * ATLAS_SIZE + page.dirty_min.x) * 4
			copy(store.upload[y * size.x * 4:(y + 1) * size.x * 4], page.pixels[src:src + size.x * 4])
		}
		if platform.update_image(renderer, page.image, store.upload[:], page.dirty_min, size) != .None { return .Upload_Failed }
		page.dirty = false
	}
	return .None
}

@(private)
configure_font :: proc(font: ^Font_Record, px: i32, w: c.long) -> Error {
	if font.pixel_size != px || font.weight != w {
		if font.weight_axis >= 0 && (font.pixel_size == 0 || font.weight != w) {
			font.coords[font.weight_axis] = w
			if native.FT_Set_Var_Design_Coordinates(font.face, font.axes.num_axis, raw_data(font.coords)) != 0 { return .Invalid_Weight }
		}
		if native.FT_Set_Char_Size(font.face, 0, c.long(px), 72, 72) != 0 { return .Invalid_Size }
		native.hb_ft_font_changed(font.hb)
		font.pixel_size, font.weight = px, w
	}
	return .None
}
