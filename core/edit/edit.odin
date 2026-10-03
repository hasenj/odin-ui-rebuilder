// Single-line text editing data. No window, renderer, font or native dependency.
package edit

import "../input"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

Range :: input.Text_Range
Operation :: input.Text_Operation
Command :: input.Text_Command
NONE :: input.NO_TEXT_RANGE

Buffer :: struct {
	bytes: [dynamic]u8,
	anchor, cursor: int,
	marked: Range,
	undo, redo: [dynamic]Snapshot,
	composition: Snapshot,
	composing: bool,
	revision: u64,
}
Snapshot :: struct {value: string, anchor, cursor: int}

value :: proc(b: ^Buffer) -> string { return string(b.bytes[:]) }
selection :: proc(b: ^Buffer) -> Range { return {min(b.anchor, b.cursor), max(b.anchor, b.cursor)} }
init :: proc(b: ^Buffer, text: string = "") { append(&b.bytes, ..transmute([]u8)text); b.cursor = len(b.bytes); b.anchor = b.cursor; b.marked = NONE }
destroy :: proc(b: ^Buffer) {
	delete(b.bytes)
	clear_history(&b.undo); delete(b.undo)
	clear_history(&b.redo); delete(b.redo)
	delete(b.composition.value)
	b^ = {}
}

// Range changes clamp to UTF-8 boundaries. Navigation/deletion uses graphemes.
select :: proc(b: ^Buffer, anchor, cursor: int) {
	b.anchor, b.cursor = boundary(value(b), anchor), boundary(value(b), cursor)
}

apply :: proc(b: ^Buffer, op: Operation) {
	switch op.kind {
	case .Commit, .Mark:
		range := op.replacement
		if !op.has_replacement { range = b.marked if b.composing else selection(b) }
		if op.kind == .Mark {
			if !b.composing { b.composition = snapshot(b); b.composing = true }
		} else {
			if b.composing {
				push(&b.undo, b.composition); b.composition = {}; b.composing = false
			} else { push(&b.undo, snapshot(b)) }
			clear_history(&b.redo)
		}
		start, count := replace(b, range, op.text)
		if op.kind == .Mark {
			b.marked = {start, start + count}
			select(b, start + clamp(op.selection.start, 0, count), start + clamp(op.selection.end, 0, count))
		} else { b.marked = NONE }
	case .Unmark:
		finish_composition(b)
	case .Cancel_Composition:
		if b.composing {
			restore(b, b.composition)
			delete(b.composition.value); b.composition = {}; b.composing = false; b.marked = NONE
		}
	case .Command:
		if op.command == .Cancel { apply(b, {kind = .Cancel_Composition}); return }
		finish_composition(b)
		command(b, op.command, op.extend)
	}
}

finish_composition :: proc(b: ^Buffer) {
	if b.composing {
		push(&b.undo, b.composition); b.composition = {}; b.composing = false
		clear_history(&b.redo)
	}
	b.marked = NONE
}

command :: proc(b: ^Buffer, cmd: Command, extend: bool = false) {
	range := selection(b)
	next := b.cursor
	switch cmd {
	case .Left: next = previous(value(b), b.cursor) if extend || range.start == range.end else range.start
	case .Right: next = following(value(b), b.cursor) if extend || range.start == range.end else range.end
	case .Word_Left: next = word_previous(value(b), b.cursor)
	case .Word_Right: next = word_following(value(b), b.cursor)
	case .Home: next = 0
	case .End: next = len(b.bytes)
	case .Select_All: b.anchor, b.cursor = 0, len(b.bytes); return
	case .Backspace, .Delete, .Delete_Word_Backward, .Delete_Word_Forward:
		if range.start == range.end {
			if cmd == .Backspace { range.start = previous(value(b), b.cursor) }
			if cmd == .Delete { range.end = following(value(b), b.cursor) }
			if cmd == .Delete_Word_Backward { range.start = word_previous(value(b), b.cursor) }
			if cmd == .Delete_Word_Forward { range.end = word_following(value(b), b.cursor) }
		}
		if range.start != range.end { apply(b, {kind = .Commit, replacement = range, has_replacement = true}) }
		return
	case .Undo:
		if len(b.undo) > 0 { push(&b.redo, snapshot(b)); old := pop(&b.undo); restore(b, old); delete(old.value) }
		return
	case .Redo:
		if len(b.redo) > 0 { push(&b.undo, snapshot(b)); old := pop(&b.redo); restore(b, old); delete(old.value) }
		return
	case .Copy, .Cut, .Paste, .Submit, .Cancel: return // Services belong to the caller.
	}
	b.cursor = next
	if !extend { b.anchor = next }
}

// Grapheme traversal uses Odin's Unicode segmentation (including combining
// sequences, emoji modifiers, ZWJ sequences and regional-indicator pairs).
previous :: proc(text: string, at: int) -> int {
	last := 0
	it := utf8.decode_grapheme_iterator_make(text)
	for { _, g, ok := utf8.decode_grapheme_iterate(&it); if !ok { break }; if g.byte_index >= at { break }; last = g.byte_index }
	return last
}
following :: proc(text: string, at: int) -> int {
	it := utf8.decode_grapheme_iterator_make(text)
	for { _, g, ok := utf8.decode_grapheme_iterate(&it); if !ok { break }; if g.byte_index > at { return g.byte_index } }
	return len(text)
}
@(private) boundary :: proc(text: string, position: int) -> int {
	at := clamp(position, 0, len(text))
	for at > 0 && at < len(text) && text[at] & 0xc0 == 0x80 { at -= 1 }
	return at
}
@(private) space_at :: proc(text: string, at: int) -> bool {
	if at >= len(text) { return true }
	r, _ := utf8.decode_rune_in_string(text[at:]); return unicode.is_space(r)
}
word_previous :: proc(text: string, position: int) -> int {
	previous_start := 0
	current_start := -1
	it := utf8.decode_grapheme_iterator_make(text)
	for {
		_, g, ok := utf8.decode_grapheme_iterate(&it)
		if !ok || g.byte_index >= position { break }
		if space_at(text, g.byte_index) {
			if current_start >= 0 { previous_start = current_start }; current_start = -1
		} else if current_start < 0 { current_start = g.byte_index }
	}
	return current_start if current_start >= 0 else previous_start
}
word_following :: proc(text: string, position: int) -> int {
	gap := false
	it := utf8.decode_grapheme_iterator_make(text)
	for {
		_, g, ok := utf8.decode_grapheme_iterate(&it)
		if !ok { break }
		if g.byte_index < position { continue }
		if space_at(text, g.byte_index) { gap = true } else if gap { return g.byte_index }
	}
	return len(text)
}
@(private) snapshot :: proc(b: ^Buffer) -> Snapshot { return {strings.clone(value(b)), b.anchor, b.cursor} }
@(private) restore :: proc(b: ^Buffer, s: Snapshot) { clear(&b.bytes); append(&b.bytes, ..transmute([]u8)s.value); b.anchor, b.cursor = s.anchor, s.cursor; b.revision += 1 }
@(private) clear_history :: proc(history: ^[dynamic]Snapshot) { for entry in history^ { delete(entry.value) }; clear(history) }
@(private) push :: proc(history: ^[dynamic]Snapshot, s: Snapshot) {
	if len(history^) == 128 { delete(history^[0].value); copy(history^[:], history^[1:]); resize(history, 127) }
	append(history, s)
}
@(private) replace :: proc(b: ^Buffer, range: Range, text: string) -> (int, int) {
	lo := boundary(value(b), range.start)
	hi := max(lo, boundary(value(b), range.end))
	// Sanitize pasted/committed line breaks for the single-line model. Copy
	// before mutating: callers may supply a substring of this same buffer.
	insert := make([dynamic]u8, 0, len(text), context.temp_allocator)
	for raw in text { r := raw; if r == '\r' || r == '\n' || r == '\t' { r = ' ' }; if r < 0x20 || r == 0x7f { continue }; bytes, n := utf8.encode_rune(r); append(&insert, ..bytes[:n]) }
	old := len(b.bytes)
	change := len(insert) - (hi - lo)
	if change > 0 { resize(&b.bytes, old + change) }
	copy(b.bytes[lo + len(insert):old + change], b.bytes[hi:old])
	copy(b.bytes[lo:lo + len(insert)], insert[:])
	if change < 0 { resize(&b.bytes, old + change) }
	b.cursor, b.anchor = lo + len(insert), lo + len(insert)
	b.revision += 1
	return lo, len(insert)
}
