package text

import "native"
import "core:strings"

// Width-independent data. A cache entry owns the UTF-8 buffer referenced by
// SheenBidi; paragraphs are released before that buffer. No retained font pointers.
@(private)
Paragraph_Run :: struct {start, end, first, last: int, rtl: bool}
@(private)
Hard_Line :: struct {start, end, first_word, last_word: int}
@(private)
Paragraph_Entry :: struct {
	key: Run_Key,
	paragraph: native.SB_Paragraph,
	scripts: []Script_Run,
	runs: [dynamic]Paragraph_Run, // Sorted by logical byte offset; glyphs retain run order.
	infos: [dynamic]native.HB_Glyph_Info,
	positions: [dynamic]native.HB_Glyph_Position,
	prefix: []i64, // Exact 26.6 advance sums indexed by source byte boundary.
	safe: []bool, // HarfBuzz cluster boundaries at which the cached shape may split.
	words: [dynamic]Word_Bounds,
	hard_lines: [dynamic]Hard_Line,
	previous, next: int,
}
@(private)
Paragraph_Cache :: struct {
	lookup: map[Run_Key]int,
	entries: [dynamic]Paragraph_Entry,
	free: [dynamic]int,
	first, last, bytes: int,
	scratch: Paragraph_Entry, // One oversized request, not retained as a cache entry.
}
@(private)
MAX_PARAGRAPHS :: 256
@(private)
MAX_PARAGRAPH_BYTES :: 4 * 1024 * 1024

@(private)
get_paragraph :: proc(store: ^Store, font: ^Font_Record, key: Run_Key) -> (^Paragraph_Entry, Error) {
	cache := &store.paragraphs
	if index, ok := cache.lookup[key]; ok {
		touch_paragraph(cache, index)
		return &cache.entries[index - 1], .None
	}
	entry := Paragraph_Entry{key = key}
	entry.key.value = strings.clone(key.value)
	entry.key.language = strings.clone(key.language)
	if err := prepare_paragraph(store, font, &entry); err != .None {
		delete_paragraph(&entry)
		return nil, err
	}
	bytes := paragraph_bytes(&entry)
	if bytes > MAX_PARAGRAPH_BYTES {
		delete_paragraph(&cache.scratch)
		cache.scratch = entry
		return &cache.scratch, .None
	}
	for len(cache.lookup) >= MAX_PARAGRAPHS || cache.bytes + bytes > MAX_PARAGRAPH_BYTES {
		evict_paragraph(cache)
	}
	index: int
	if len(cache.free) > 0 { index = pop(&cache.free) } else {
		append(&cache.entries, Paragraph_Entry{})
		index = len(cache.entries)
	}
	cache.entries[index - 1] = entry
	cache.lookup[entry.key] = index
	cache.bytes += bytes
	touch_paragraph(cache, index)
	return &cache.entries[index - 1], .None
}

@(private)
touch_paragraph :: proc(cache: ^Paragraph_Cache, index: int) {
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
evict_paragraph :: proc(cache: ^Paragraph_Cache) {
	index := cache.last
	assert(index != 0)
	entry := &cache.entries[index - 1]
	cache.last = entry.previous
	if cache.last != 0 { cache.entries[cache.last - 1].next = 0 } else { cache.first = 0 }
	cache.bytes -= paragraph_bytes(entry)
	delete_key(&cache.lookup, entry.key)
	delete_paragraph(entry)
	append(&cache.free, index)
}

@(private)
paragraph_bytes :: proc(entry: ^Paragraph_Entry) -> int {
	// Retained native state is a byte-sized type array and level array, plus
	// fixed object headers. Include a conservative header allowance here.
	return len(entry.key.value) * 3 + len(entry.key.language) + 512 +
		len(entry.scripts) * size_of(Script_Run) + len(entry.prefix) * size_of(i64) + len(entry.safe) +
		cap(entry.runs) * size_of(Paragraph_Run) + cap(entry.infos) * size_of(native.HB_Glyph_Info) +
		cap(entry.positions) * size_of(native.HB_Glyph_Position) + cap(entry.words) * size_of(Word_Bounds) +
		cap(entry.hard_lines) * size_of(Hard_Line)
}

@(private)
delete_paragraph :: proc(entry: ^Paragraph_Entry) {
	if entry.paragraph != nil { native.SBParagraphRelease(entry.paragraph) }
	delete(entry.key.value)
	delete(entry.key.language)
	delete(entry.scripts)
	delete(entry.runs)
	delete(entry.infos)
	delete(entry.positions)
	delete(entry.prefix)
	delete(entry.safe)
	delete(entry.words)
	delete(entry.hard_lines)
	entry^ = {}
}

@(private)
destroy_paragraph_cache :: proc(cache: ^Paragraph_Cache) {
	for cache.last != 0 { evict_paragraph(cache) }
	delete_paragraph(&cache.scratch)
	delete(cache.lookup)
	delete(cache.entries)
	delete(cache.free)
	cache^ = {}
}
