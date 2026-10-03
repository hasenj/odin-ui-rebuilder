package file_manager

import ui "../../core"
import edit "../../core/edit"
import "core:strings"
import "core:unicode/utf8"

Typeahead :: struct {
	buffer: edit.Buffer,
	generation, target: u64,
	last_input: f64,
	no_match, submit: bool,
	match: int, // Only set on a query change; no per-frame listing scan.
	searches: u64,
}

clear_typeahead :: proc() {
	if cap(list.search.buffer.bytes) > 0 || list.search.buffer.composing {
		edit.destroy(&list.search.buffer)
		edit.init(&list.search.buffer)
	}
	list.search.no_match = false
}

focused_row :: proc() -> int {
	if list.generation == browser.generation {
		for row in list.rows { if row.id == ui.direct_focus() { return row.index } }
	}
	return -1
}

// Native text operations honor the active keyboard layout, dead keys and IME.
// Raw physical keys are not converted into assumed US-layout characters.
update_typeahead :: proc() {
	s := &list.search
	frame := ui.current_frame()
	s.match, s.submit = -1, false
	if s.generation != browser.generation {
		clear_typeahead()
		s.generation, s.target = browser.generation, 0
	}
	if (!s.buffer.composing && frame.time - s.last_input > 1.0) ||
	   .Left in pressed || (.Tab in frame.input.keys_pressed && .Tab not_in frame.input.text.handled_keys) { clear_typeahead() }
	selected := focused_row()
	for operation in frame.input.text.operations {
		target := operation.target if operation.target != 0 else frame.input.text.target
		if target == 0 || target != s.target { continue }
		op := operation
		before := edit.value(&s.buffer)
		repeated := op.kind == .Commit && strings.equal_fold(before, op.text) && utf8.rune_count_in_string(op.text) == 1
		start := max(selected, 0)
		if before == "" { start = selected + 1 }
		switch op.kind {
		case .Command:
			#partial switch op.command {
			case .Cancel: clear_typeahead(); continue
			case .Submit: s.submit = true; continue
			case .Backspace, .Delete:
			case .Paste:
				if value, ok := ui.clipboard_read(); ok {
					edit.apply(&s.buffer, {kind = .Commit, text = value}); delete(value)
				} else { continue }
			case: continue
			}
		case .Commit, .Mark, .Unmark, .Cancel_Composition:
		}
		if op.kind != .Command || op.command != .Paste { edit.apply(&s.buffer, op) }
		s.last_input = frame.time
		if s.buffer.composing { continue } // Do not change native focus during preedit.
		query := edit.value(&s.buffer)
		if query == "" { s.no_match = false; continue }
		s.searches += 1
		found := find_prefix(browser.entries[:], query, start)
		// Repeated single letters cycle matching entries unless the longer
		// prefix itself matches (so names such as "aardvark" remain reachable).
		if found < 0 && repeated {
			clear_typeahead()
			edit.apply(&s.buffer, {kind = .Commit, text = op.text})
			found = find_prefix(browser.entries[:], edit.value(&s.buffer), selected + 1)
		}
		s.no_match = found < 0
		if found >= 0 { s.match, selected = found, found }
	}
}

// No case-folded copy of every filename, and no work while the query is idle.
find_prefix :: proc(entries: []Entry, query: string, start: int) -> int {
	if len(entries) == 0 || query == "" { return -1 }
	count := utf8.rune_count_in_string(query)
	for n in 0..<len(entries) {
		i := (max(start, 0) + n) % len(entries)
		name := entries[i].info.name
		end := 0
		for _ in 0..<count {
			if end == len(name) { break }
			_, size := utf8.decode_rune_in_string(name[end:]); end += size
		}
		if strings.equal_fold(name[:end], query) { return i }
	}
	return -1
}

publish_typeahead :: proc() {
	if ui.direct_focus() != ui.current_identity() { return }
	s := &list.search
	value := edit.value(&s.buffer)
	// The footer exposes the transient query and anchors native IME candidates.
	frame := ui.current_frame()
	caret := ui.Rect{{10, max(0, frame.size.y - footer_height + 3)}, {1, 18}}
	ui.request_text_input(value, edit.selection(&s.buffer), caret,
		s.buffer.marked if s.buffer.composing else {-1, -1})
	s.target = ui.text_target(ui.current_identity())
}
