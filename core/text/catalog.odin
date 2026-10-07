package text

import "native"
import c "core:c"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:slice"
import "core:fmt"

// A metadata-only snapshot. FreeType faces used for discovery are closed before
// returning; shaping faces and GPU glyphs are created only when requested.
Font_Info :: struct {
	family, style, path: string,
	face_index: int,
}
@(private) Coverage_Range :: struct {first, last: rune}
@(private) Catalog_Face :: struct {
	info: Font_Info,
	coverage: [dynamic]Coverage_Range,
	rank: int,
	loaded: Font,
	failed: bool,
}
@(private) Font_Catalog :: struct {
	faces: [dynamic]Catalog_Face,
	names: map[string]int,
	resolved: map[string]Font,
	pages: map[u32][dynamic]int, // Unicode page -> candidate faces, in preference order.
	choices: map[string]int, // Complete run/grapheme -> face + 1, including zero misses.
	queries: u64,
}

// Explicit startup/refresh operation; never scans from measurement or painting.
// Missing directories and unsupported font files are skipped. An empty paths
// slice selects conventional OS directories. Returns the number of usable faces.
// Must run on the store's owning thread, outside text drawing operations.
discover_fonts :: proc(store: ^Store, paths: []string = nil) -> (int, Error) {
	if err := init_library(store); err != .None { return 0, err }
	catalog: Font_Catalog
	paths := paths
	roots: [dynamic]string
	if len(paths) == 0 {
		home, _ := os.user_home_dir(context.allocator)
		defer delete(home)
		when ODIN_OS == .Darwin {
			append(&roots, strings.clone("/System/Library/Fonts"), strings.clone("/Library/Fonts"), fmt.aprintf("%s/Library/Fonts", home))
		} else when ODIN_OS == .Linux {
			data := os.get_env("XDG_DATA_HOME", context.allocator)
			defer delete(data)
			append(&roots, fmt.aprintf("%s/fonts", data) if data != "" else fmt.aprintf("%s/.local/share/fonts", home), fmt.aprintf("%s/.fonts", home))
			dirs := os.get_env("XDG_DATA_DIRS", context.allocator)
			defer delete(dirs)
			remaining := dirs
			for dir in strings.split_iterator(&remaining, ":") { if dir != "" { append(&roots, fmt.aprintf("%s/fonts", dir)) } }
			append(&roots, strings.clone("/usr/local/share/fonts"), strings.clone("/usr/share/fonts"))
		} else when ODIN_OS == .Windows {
			windows := os.get_env("WINDIR", context.allocator)
			local := os.get_env("LOCALAPPDATA", context.allocator)
			defer delete(windows); defer delete(local)
			append(&roots, fmt.aprintf("%s/Fonts", windows), fmt.aprintf("%s/Microsoft/Windows/Fonts", local))
		}
		paths = roots[:]
	}
	defer { for path in roots { delete(path) }; delete(roots) }
	files: [dynamic]string
	seen: map[string]bool
	defer { for file in files { delete(file) }; delete(files); delete(seen) }
	for root in paths {
		walker := os.walker_create(root)
		for info in os.walker_walk(&walker) {
			if info.type == .Directory || info.fullpath == "" { continue }
			ext := strings.to_lower(filepath.ext(info.fullpath))
			font_file := ext == ".ttf" || ext == ".otf" || ext == ".ttc" || ext == ".otc"
			delete(ext)
			if font_file && !seen[info.fullpath] {
				path := strings.clone(info.fullpath)
				seen[path] = true; append(&files, path)
			}
		}
		os.walker_destroy(&walker)
	}
	slice.sort(files[:]) // Reproducible fallback independent of filesystem iteration.
	for path in files { catalog_scan_file(store.library, &catalog, path) }
	slice.sort_by(catalog.faces[:], proc(a, b: Catalog_Face) -> bool {
		if a.rank != b.rank { return a.rank < b.rank }
		if a.info.path != b.info.path { return a.info.path < b.info.path }
		return a.info.face_index < b.info.face_index
	})
	for face, i in catalog.faces {
		catalog_add_name(&catalog, face.info.family, i)
		full := fmt.aprintf("%s %s", face.info.family, face.info.style)
		catalog_add_name(&catalog, full, i); delete(full)
		last_page := u32(max(u32))
		for range in face.coverage {
			for page in u32(range.first) >> 8..=u32(range.last) >> 8 {
				if page == last_page { continue }
				list := catalog.pages[page]; append(&list, i); catalog.pages[page] = list
				last_page = page
			}
		}
	}
	destroy_catalog(&store.catalog)
	store.catalog = catalog
	store.catalog_generation += 1
	destroy_run_cache(&store.runs)
	destroy_paragraph_cache(&store.paragraphs)
	return len(catalog.faces), .None
}

// Borrowed metadata, valid until discovery refresh or store destruction.
font_catalog_count :: proc(store: ^Store) -> int { return len(store.catalog.faces) }
font_catalog_info :: proc(store: ^Store, index: int) -> Font_Info {
	assert(index >= 0 && index < len(store.catalog.faces))
	return store.catalog.faces[index].info
}

@(private)
catalog_scan_file :: proc(library: native.FT_Library, catalog: ^Font_Catalog, path: string) {
	filename := strings.clone_to_cstring(path); defer delete(filename)
	count := 1
	for index := 0; index < count; index += 1 {
		face: ^native.FT_Face
		if native.FT_New_Face(library, filename, c.long(index), &face) != 0 { continue }
		count = int(face.num_faces)
		// Our atlas accepts scalable monochrome outlines. Color/bitmap emoji
		// need a separate rendering path, so do not falsely advertise support.
		if face.units_per_em > 0 && face.face_flags & (1 << 14) == 0 && native.FT_Select_Charmap(face, 0x756e6963) == 0 && face.family_name != nil {
			record := Catalog_Face{info = {strings.clone(string(face.family_name)), strings.clone(string(face.style_name)), strings.clone(path), index}}
			style := strings.to_lower(record.info.style)
			record.rank = int(face.style_flags & 3) * 10
			if style != "regular" && style != "normal" && style != "roman" && style != "book" { record.rank += 1 }
			delete(style)
			glyph: c.uint
			code := native.FT_Get_First_Char(face, &glyph)
			for glyph != 0 && code <= 0x10ffff {
				last := len(record.coverage) - 1
				if last >= 0 && record.coverage[last].last + 1 == rune(code) { record.coverage[last].last = rune(code) } else {
					append(&record.coverage, Coverage_Range{rune(code), rune(code)})
				}
				code = native.FT_Get_Next_Char(face, code, &glyph)
			}
			append(&catalog.faces, record)
		}
		native.FT_Done_Face(face)
	}
}

@(private)
catalog_add_name :: proc(catalog: ^Font_Catalog, name: string, index: int) {
	key := strings.to_lower(name)
	if _, exists := catalog.names[key]; exists { delete(key) } else { catalog.names[key] = index }
}

@(private)
catalog_load :: proc(store: ^Store, index: int) -> Font {
	face := &store.catalog.faces[index]
	if face.loaded != 0 || face.failed { return face.loaded }
	// Private aliases avoid collisions between styles/collections and app aliases.
	name := fmt.aprintf("@system:%s:%d", face.info.path, face.info.face_index)
	defer delete(name)
	if handle, ok := store.names[name]; ok { face.loaded = handle; return handle }
	handle, err := load(store, face.info.path, name, face.info.face_index)
	face.loaded, face.failed = handle, err != .None
	return handle
}

@(private)
catalog_find :: proc(store: ^Store, name: string) -> (Font, bool) {
	if handle, known := store.catalog.resolved[name]; known { return handle, handle != 0 }
	key := strings.to_lower(name); defer delete(key)
	index, ok := store.catalog.names[key]
	handle: Font
	if ok { handle = catalog_load(store, index) }
	if len(store.catalog.resolved) >= 2048 {
		for alias in store.catalog.resolved { delete(alias) }; clear(&store.catalog.resolved)
	}
	store.catalog.resolved[strings.clone(name)] = handle
	return handle, handle != 0
}

@(private)
catalog_covers :: proc(face: ^Catalog_Face, value: string) -> bool {
	for ch in value {
		if coverage_ignorable(ch) { continue }
		low, high := 0, len(face.coverage)
		for low < high {
			mid := low + (high - low) / 2
			if face.coverage[mid].last < ch { low = mid + 1 } else { high = mid }
		}
		if low == len(face.coverage) || face.coverage[low].first > ch { return false }
	}
	return true
}

@(private)
catalog_choose :: proc(store: ^Store, value: string) -> Font {
	catalog := &store.catalog
	if len(catalog.faces) == 0 { return 0 }
	if index, found := catalog.choices[value]; found {
		if index == 0 { return 0 }; return catalog_load(store, index - 1)
	}
	catalog.queries += 1
	candidates: []int
	for ch in value {
		if !coverage_ignorable(ch) { candidates = catalog.pages[u32(ch) >> 8][:]; break }
	}
	choice := 0
	for index in candidates {
		if catalog_covers(&catalog.faces[index], value) && catalog_load(store, index) != 0 { choice = index + 1; break }
	}
	// Bound source-string retention even with an unbounded stream of unique text.
	if len(catalog.choices) >= 2048 {
		for key in catalog.choices { delete(key) }; clear(&catalog.choices)
	}
	catalog.choices[strings.clone(value)] = choice
	if choice == 0 { return 0 }; return catalog.faces[choice - 1].loaded
}

@(private)
destroy_catalog :: proc(catalog: ^Font_Catalog) {
	for face in catalog.faces { delete(face.info.family); delete(face.info.style); delete(face.info.path); delete(face.coverage) }
	for key in catalog.names { delete(key) }
	for key in catalog.resolved { delete(key) }
	for _, page in catalog.pages { delete(page) }
	for key in catalog.choices { delete(key) }
	delete(catalog.faces); delete(catalog.names); delete(catalog.resolved); delete(catalog.pages); delete(catalog.choices)
	catalog^ = {}
}

// Resolve an exact catalog face (including collection index/style).
load_catalog_font :: proc(store: ^Store, index: int) -> (Font, Error) {
	if index < 0 || index >= len(store.catalog.faces) { return 0, .Invalid_Font }
	font := catalog_load(store, index)
	return font, .None if font != 0 else .Font_Load_Failed
}
