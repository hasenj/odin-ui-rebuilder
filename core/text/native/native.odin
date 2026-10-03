// Narrow C ABI bindings for FreeType 2 and HarfBuzz. Link with pkg-config paths
// through scripts/build.sh. No platform-native text APIs or C shim are used.
package native

import c "core:c"

foreign import freetype "system:freetype"
foreign import harfbuzz "system:harfbuzz"

FT_Library :: distinct rawptr
FT_Generic :: struct {data, finalizer: rawptr}
FT_Vector :: struct {x, y: c.long}
FT_BBox :: struct {x_min, y_min, x_max, y_max: c.long}

// Public struct prefixes only. These objects are always allocated by FreeType;
// never allocate or pass them by value from Odin.
FT_Face :: struct {
	num_faces, face_index, face_flags, style_flags, num_glyphs: c.long,
	family_name, style_name: cstring,
	num_fixed_sizes: c.int,
	available_sizes: rawptr,
	num_charmaps: c.int,
	charmaps: rawptr,
	generic: FT_Generic,
	bbox: FT_BBox,
	units_per_em: u16,
	ascender, descender, height: i16,
	max_advance_width, max_advance_height: i16,
	underline_position, underline_thickness: i16,
	glyph: ^FT_Glyph_Slot,
	size: ^FT_Size,
	charmap: rawptr,
}
FT_Size_Metrics :: struct {
	x_ppem, y_ppem: u16,
	x_scale, y_scale, ascender, descender, height, max_advance: c.long,
}
FT_Size :: struct {face: ^FT_Face, generic: FT_Generic, metrics: FT_Size_Metrics}
FT_Bitmap :: struct {
	rows, width: c.uint,
	pitch: c.int,
	buffer: [^]u8,
	num_grays: u16,
	pixel_mode, palette_mode: u8,
	palette: rawptr,
}
FT_Glyph_Slot :: struct {
	library: FT_Library,
	face: ^FT_Face,
	next: ^FT_Glyph_Slot,
	glyph_index: c.uint,
	generic: FT_Generic,
	metrics: [8]c.long,
	linear_hori_advance, linear_vert_advance: c.long,
	advance: FT_Vector,
	format: c.uint,
	bitmap: FT_Bitmap,
	bitmap_left, bitmap_top: c.int,
}
FT_Var_Axis :: struct {name: cstring, minimum, def, maximum: c.long, tag: c.ulong, strid: c.uint}
FT_MM_Var :: struct {num_axis, num_designs, num_namedstyles: c.uint, axis: [^]FT_Var_Axis, namedstyle: rawptr}

FT_LOAD_NO_HINTING :: 1 << 1
FT_LOAD_NO_BITMAP :: 1 << 3
FT_PIXEL_MODE_GRAY :: 2
FT_FACE_FLAG_MULTIPLE_MASTERS :: 1 << 8

@(default_calling_convention="c")
foreign freetype {
	FT_Init_FreeType :: proc(library: ^FT_Library) -> c.int ---
	FT_Done_FreeType :: proc(library: FT_Library) -> c.int ---
	FT_New_Face :: proc(library: FT_Library, path: cstring, index: c.long, face: ^^FT_Face) -> c.int ---
	FT_Done_Face :: proc(face: ^FT_Face) -> c.int ---
	FT_Select_Charmap :: proc(face: ^FT_Face, encoding: c.uint) -> c.int ---
	FT_Get_Char_Index :: proc(face: ^FT_Face, codepoint: c.ulong) -> c.uint ---
	FT_Set_Char_Size :: proc(face: ^FT_Face, width, height: c.long, horizontal_dpi, vertical_dpi: c.uint) -> c.int ---
	FT_Load_Glyph :: proc(face: ^FT_Face, glyph: c.uint, flags: i32) -> c.int ---
	FT_Render_Glyph :: proc(slot: ^FT_Glyph_Slot, mode: c.int) -> c.int ---
	FT_Get_MM_Var :: proc(face: ^FT_Face, info: ^^FT_MM_Var) -> c.int ---
	FT_Done_MM_Var :: proc(library: FT_Library, info: ^FT_MM_Var) -> c.int ---
	FT_Set_Var_Design_Coordinates :: proc(face: ^FT_Face, count: c.uint, coords: [^]c.long) -> c.int ---
}

HB_Font :: distinct rawptr
HB_Buffer :: distinct rawptr
HB_Language :: distinct rawptr
HB_Glyph_Info :: struct {codepoint, mask, cluster, var1, var2: u32}
HB_Glyph_Position :: struct {x_advance, y_advance, x_offset, y_offset: i32, var: u32}
HB_Feature :: struct {tag, value, start, end: u32}

@(default_calling_convention="c")
foreign harfbuzz {
	hb_ft_font_create_referenced :: proc(face: ^FT_Face) -> HB_Font ---
	hb_ft_font_set_load_flags :: proc(font: HB_Font, flags: c.int) ---
	hb_ft_font_changed :: proc(font: HB_Font) ---
	hb_font_destroy :: proc(font: HB_Font) ---
	hb_buffer_create :: proc() -> HB_Buffer ---
	hb_buffer_destroy :: proc(buffer: HB_Buffer) ---
	hb_buffer_clear_contents :: proc(buffer: HB_Buffer) ---
	hb_buffer_add_utf8 :: proc(buffer: HB_Buffer, text: rawptr, length: c.int, item_offset: c.uint, item_length: c.int) ---
	hb_buffer_set_flags :: proc(buffer: HB_Buffer, flags: u32) ---
	hb_buffer_set_direction :: proc(buffer: HB_Buffer, direction: c.int) ---
	hb_buffer_set_script :: proc(buffer: HB_Buffer, script: u32) ---
	hb_buffer_set_language :: proc(buffer: HB_Buffer, language: HB_Language) ---
	hb_language_from_string :: proc(text: cstring, length: c.int) -> HB_Language ---
	hb_shape :: proc(font: HB_Font, buffer: HB_Buffer, features: [^]HB_Feature, count: c.uint) ---
	hb_buffer_allocation_successful :: proc(buffer: HB_Buffer) -> c.int ---
	hb_buffer_get_length :: proc(buffer: HB_Buffer) -> c.uint ---
	hb_buffer_get_glyph_infos :: proc(buffer: HB_Buffer, length: ^c.uint) -> [^]HB_Glyph_Info ---
	hb_buffer_get_glyph_positions :: proc(buffer: HB_Buffer, length: ^c.uint) -> [^]HB_Glyph_Position ---
}

// Verified against the public FreeType headers on the supported 64-bit Unix ABI.
when size_of(rawptr) == 8 && size_of(c.long) == 8 {
	#assert(offset_of(FT_Face, glyph) == 152)
	#assert(offset_of(FT_Face, size) == 160)
	#assert(offset_of(FT_Face, charmap) == 168)
	#assert(offset_of(FT_Size, metrics) == 24)
	#assert(offset_of(FT_Glyph_Slot, bitmap) == 152)
	#assert(offset_of(FT_Glyph_Slot, bitmap_top) == 196)
	#assert(offset_of(FT_MM_Var, axis) == 16)
	#assert(offset_of(FT_Var_Axis, tag) == 32)
	#assert(size_of(FT_Bitmap) == 40)
	#assert(size_of(FT_Size_Metrics) == 56)
	#assert(size_of(FT_Var_Axis) == 48)
}
#assert(size_of(HB_Glyph_Info) == 20)
#assert(size_of(HB_Glyph_Position) == 20)
