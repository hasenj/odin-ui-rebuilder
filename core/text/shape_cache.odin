package text

import "native"
import c "core:c"
import "core:strings"

// Entries own their string and glyph slices. A string value in the key compares
// contents, including for callers that reuse a stack buffer each frame.
@(private)
Run_Key :: struct {font: Font, pixel_size: i32, weight: c.long, value: string}
@(private)
Run_Entry :: struct {
	key: Run_Key,
	infos: []native.HB_Glyph_Info,
	positions: []native.HB_Glyph_Position,
	metrics: Metrics,
	previous, next: int, // One-based array indices; zero terminates the LRU list.
}
@(private)
Run_Cache :: struct {
	lookup: map[Run_Key]int,
	entries: [dynamic]Run_Entry,
	free: [dynamic]int,
	first, last, bytes: int,
}
@(private)
MAX_RUNS :: 1024
@(private)
MAX_RUN_BYTES :: 4 * 1024 * 1024 // Owned text and glyph data; metadata is bounded separately.

// The returned slices are borrowed until the next shape call. Font pointers are
// never stored: loading another font can relocate the font array.
@(private)
lookup_run :: proc(cache: ^Run_Cache, key: Run_Key, font: ^Font_Record) -> (Shape, bool) {
	index, ok := cache.lookup[key]
	if !ok { return {}, false }
	touch_run(cache, index)
	entry := &cache.entries[index - 1]
	return {font = font, infos = entry.infos, positions = entry.positions,
		metrics = entry.metrics, pixel_size = key.pixel_size, weight = key.weight}, true
}

@(private)
store_run :: proc(cache: ^Run_Cache, key: Run_Key, run: Shape) -> Shape {
	bytes := len(key.value) + len(run.infos) * size_of(native.HB_Glyph_Info) + len(run.positions) * size_of(native.HB_Glyph_Position)
	// Very large runs still render, but do not displace the entire working set.
	if bytes > MAX_RUN_BYTES { return run }
	for len(cache.lookup) >= MAX_RUNS || cache.bytes + bytes > MAX_RUN_BYTES {
		evict_run(cache)
	}
	index: int
	if len(cache.free) > 0 {
		index = pop(&cache.free)
	} else {
		append(&cache.entries, Run_Entry{})
		index = len(cache.entries)
	}
	owned_key := key
	owned_key.value = strings.clone(key.value)
	entry := &cache.entries[index - 1]
	entry^ = {key = owned_key, infos = make([]native.HB_Glyph_Info, len(run.infos)),
		positions = make([]native.HB_Glyph_Position, len(run.positions)), metrics = run.metrics}
	copy(entry.infos, run.infos)
	copy(entry.positions, run.positions)
	cache.lookup[owned_key] = index
	cache.bytes += bytes
	touch_run(cache, index)
	result := run
	result.infos, result.positions = entry.infos, entry.positions
	return result
}

@(private)
touch_run :: proc(cache: ^Run_Cache, index: int) {
	if cache.first == index { return }
	entry := &cache.entries[index - 1]
	if entry.previous != 0 { cache.entries[entry.previous - 1].next = entry.next }
	if entry.next != 0 { cache.entries[entry.next - 1].previous = entry.previous }
	if cache.last == index { cache.last = entry.previous }
	entry.previous, entry.next = 0, cache.first
	if cache.first != 0 { cache.entries[cache.first - 1].previous = index }
	cache.first = index
	if cache.last == 0 { cache.last = index }
}

@(private)
evict_run :: proc(cache: ^Run_Cache) {
	index := cache.last
	assert(index != 0)
	entry := &cache.entries[index - 1]
	cache.last = entry.previous
	if cache.last != 0 { cache.entries[cache.last - 1].next = 0 } else { cache.first = 0 }
	cache.bytes -= len(entry.key.value) + len(entry.infos) * size_of(native.HB_Glyph_Info) + len(entry.positions) * size_of(native.HB_Glyph_Position)
	delete_key(&cache.lookup, entry.key)
	delete(entry.key.value)
	delete(entry.infos)
	delete(entry.positions)
	entry^ = {}
	append(&cache.free, index)
}

@(private)
destroy_run_cache :: proc(cache: ^Run_Cache) {
	for cache.last != 0 { evict_run(cache) }
	delete(cache.lookup)
	delete(cache.entries)
	delete(cache.free)
	cache^ = {}
}
