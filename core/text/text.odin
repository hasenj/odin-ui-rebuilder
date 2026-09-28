// Bidi/script shaping, word wrapping, and cached grayscale glyphs. Geometry uses physical
// pixels internally; the UI wrapper converts to/from logical window points.
package text

import "native"
import c "core:c"
import "core:math"
import "core:strings"
import "core:unicode/utf8"
import "../../platform"
import "../primitives"

// O(1) handle into a window-owned append-only font table. No slot reuse/unload in
// this stage: handles stay valid until the window closes, regardless of resizing.
Font :: distinct u32
Error :: enum {
	None, Font_Load_Failed, Invalid_Font, Name_Exists, Invalid_Size,
	Invalid_Weight, Unsupported_Weight, Unsupported_Text, Missing_Glyph,
	Shaping_Failed, Rasterization_Failed, Atlas_Full, Upload_Failed, Invalid_Width, Invalid_Scale, Invalid_Height,
}
Metrics :: struct {width, height, ascent, descent: f32}
Direction :: enum u8 {Auto, LTR, RTL}

Store :: struct {
	library: native.FT_Library,
	buffer: native.HB_Buffer,
	fonts: [dynamic]Font_Record,
	names: map[string]Font,
	pages: [dynamic]Page,
	upload: [dynamic]u8,
	runs: Run_Cache,
	paragraphs: Paragraph_Cache,
	wrap_reshapes: u64,
	shape_calls, shape_cache_hits: u64,
	geometry_builds: u64,
	quad_scratch: [dynamic]Glyph_Quad,
	script_locator: native.SB_Script_Locator,
	script_runs: [dynamic]Script_Run,
	info_scratch: [dynamic]native.HB_Glyph_Info,
	position_scratch: [dynamic]native.HB_Glyph_Position,
	bidi_calls: u64,
	wrap_infos: [dynamic]native.HB_Glyph_Info,
	wrap_positions: [dynamic]native.HB_Glyph_Position,
	wrap_lines: [dynamic]Layout_Line,
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
	destroy_paragraph_cache(&store.paragraphs)
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
	delete(store.quad_scratch)
	delete(store.script_runs)
	delete(store.info_scratch)
	delete(store.position_scratch)
	delete(store.wrap_infos)
	delete(store.wrap_positions)
	delete(store.wrap_lines)
	if store.script_locator != nil { native.SBScriptLocatorRelease(store.script_locator) }
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
	lines: []Layout_Line, // Nil for the original single-line path.
	line_height: f32,
	cache_index: int, // Borrowed run-cache slot; zero for an uncached oversized run.
}

// Returned glyph slices are borrowed until the next shape call. Cache hits
// avoid HarfBuzz and leave the current native font size/weight untouched.
@(private)
shape :: proc(store: ^Store, handle: Font, value: string, pixel_size, weight: f32, direction: Direction = .Auto, language: string = "", wrap_width: f32 = -1) -> (Shape, Error) {
	if handle == 0 || int(handle) > len(store.fonts) { return {}, .Invalid_Font }
	if !(pixel_size > 0 && pixel_size <= 2048) { return {}, .Invalid_Size }
	if !(weight >= 0 && weight <= 32767) { return {}, .Invalid_Weight }
	if len(value) > int(max(i32)) || len(language) > int(max(i32)) { return {}, .Unsupported_Text }
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
	wrapped := wrap_width >= 0
	width: i32
	if wrapped {
		if !(f64(wrap_width) * 64 <= f64(max(i32))) { return {}, .Invalid_Width }
		width = i32(math.floor(wrap_width * 64))
	}
	key := Run_Key{wrapped = wrapped, width = width, font = handle, pixel_size = px, weight = w, value = value, direction = direction, language = language}
	if cached, ok := lookup_run(&store.runs, key, font); ok {
		store.shape_cache_hits += 1
		return cached, .None
	}
	if !utf8.valid_string(value) { return {}, .Unsupported_Text }
	for ch in value {
		if wrapped && (ch == '\n' || ch == '\r' || ch == '\u2028' || ch == '\u2029' || ch == '\u0085') { continue }
		if ch == '\n' || ch == '\r' || ch == '\t' || ch == '\u2028' || ch == '\u2029' || ch == '\u0085' || ch == '\v' || ch == '\f' || (ch >= '\u001c' && ch <= '\u001e') { return {}, .Unsupported_Text }
	}
	if err := configure_font(font, px, w); err != .None { return {}, err }
	m := font.face.size.metrics
	metrics := Metrics{height = f32(m.height) / 64, ascent = f32(m.ascender) / 64, descent = -f32(m.descender) / 64}
	run := Shape{font = font, metrics = metrics, pixel_size = px, weight = w, line_height = metrics.height}
	if wrapped {
		if err := shape_wrapped(store, &run, value, f32(width) / 64, direction, language, handle); err != .None { return {}, err }
	} else {
		if err := shape_line(store, font, value, direction, language); err != .None { return {}, err }
		run.infos, run.positions = store.info_scratch[:], store.position_scratch[:]
		for info, i in run.infos {
			if info.codepoint == 0 { return {}, .Missing_Glyph }
			run.metrics.width += f32(run.positions[i].x_advance) / 64
		}
	}
	return store_run(&store.runs, key, run), .None
}

measure :: proc(store: ^Store, font: Font, value: string, size, scale, weight: f32, direction: Direction = .Auto, language: string = "") -> (Metrics, Error) {
	if !(scale > 0 && scale <= 16) { return {}, .Invalid_Size }
	run, err := shape(store, font, value, size * scale, weight, direction, language)
	return logical_metrics(run.metrics, scale), err
}

// Measurement and drawing share shaped runs. Warm text avoids shaping, native
// font reconfiguration, rasterization, uploads, and allocation.
draw :: proc(store: ^Store, renderer: platform.Renderer, font: Font, value: string, size, scale, weight: f32,
	position: [2]f32, color: primitives.Color, surfaces: ^[dynamic]primitives.Surface, direction: Direction = .Auto, language: string = "") -> (Metrics, Error) {
	if !(scale > 0 && scale <= 16) { return {}, .Invalid_Size }
	run, err := shape(store, font, value, size * scale, weight, direction, language)
	if err != .None { return {}, err }
	return draw_shape(store, renderer, run, position, color, surfaces, scale)
}

@(private)
draw_shape :: proc(store: ^Store, renderer: platform.Renderer, run: Shape, position: [2]f32, color: primitives.Color, surfaces: ^[dynamic]primitives.Surface, scale: f32, width: f32 = 0, align: Align = .Start) -> (Metrics, Error) {
	quads, prepare_error := prepare_quads(store, run)
	if prepare_error != .None { return {}, prepare_error }
	start := len(surfaces^)
	// Grow once for the entire run, then write directly into the output slice.
	// Failure must not leave partially emitted text in the frame.
	succeeded := false
	defer { if !succeeded { resize(surfaces, start) } }
	resize(surfaces, start + len(quads))
	origin := position
	aligned_line := -1
	for quad, i in quads {
		page := &store.pages[quad.page]
		if page.image == (primitives.Image{}) {
			image, image_error := platform.create_image(renderer, page.pixels, {ATLAS_SIZE, ATLAS_SIZE})
			if image_error != .None { return {}, .Upload_Failed }
			page.image = image
			page.dirty = false
		}
		if align != .Start && aligned_line != quad.line {
			line_width := run.metrics.width if len(run.lines) == 0 else run.lines[quad.line].width
			origin.x = position.x + alignment_offset(align, width - line_width / scale)
			aligned_line = quad.line
		}
		surfaces^[start + i] = place_quad(quad, page.image, origin, color, scale)
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
