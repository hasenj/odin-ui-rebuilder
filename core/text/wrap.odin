package text

// Glyph range plus source byte range. Each line is already in visual order.
@(private)
Layout_Line :: struct {start, end, byte_start, byte_end: int, width: f32}

@(private)
Word_Bounds :: struct {start, end: int}

// Initial word wrapping policy: break at ASCII spaces; preserve interior spaces,
// discard spaces at line edges, and leave overlong words intact (overflow).
// NBSP, combining sequences, ligatures, and joining sequences are never split.
// This is deliberately not a full Unicode line-breaking/hyphenation engine.
@(private)
shape_wrapped :: proc(store: ^Store, run: ^Shape, value: string, width: f32, direction: Direction, language: string, handle: Font) -> Error {
	clear(&store.wrap_infos)
	clear(&store.wrap_positions)
	clear(&store.wrap_lines)
	start := 0
	for {
		end, next := len(value), len(value) + 1
		for ch, i in value[start:] {
			if ch == '\n' || ch == '\r' || ch == '\u2029' || ch == '\u0085' {
				end = start + i
				next = end + (3 if ch == '\u2029' else 2 if ch == '\u0085' else 1)
				if ch == '\r' && next < len(value) && value[next] == '\n' { next += 1 }
				break
			}
		}
		if start == end {
			append(&store.wrap_lines, Layout_Line{start = len(store.wrap_infos), end = len(store.wrap_infos), byte_start = start, byte_end = end})
		} else {
			key := Run_Key{font = handle, pixel_size = run.pixel_size, weight = run.weight, value = value[start:end], direction = direction, language = language}
			entry, err := get_paragraph(store, run.font, key)
			if err != .None { return err }
			defer { if entry == &store.paragraphs.scratch { delete_paragraph(entry) } }
			if e := wrap_prepared(store, run.font, entry, start, width); e != .None { return e }
		}
		if next > len(value) { break }
		start = next
	}
	run.infos, run.positions, run.lines = store.wrap_infos[:], store.wrap_positions[:], store.wrap_lines[:]
	for line in run.lines { run.metrics.width = max(run.metrics.width, line.width) }
	run.metrics.height = run.line_height * f32(len(run.lines))
	return .None
}

@(private)
wrap_prepared :: proc(store: ^Store, font: ^Font_Record, entry: ^Paragraph_Entry, byte_offset: int, width: f32) -> Error {
	for hard in entry.hard_lines {
		if hard.first_word == hard.last_word {
			append(&store.wrap_lines, Layout_Line{start = len(store.wrap_infos), end = len(store.wrap_infos), byte_start = byte_offset + hard.start, byte_end = byte_offset + hard.end})
		}
		words := entry.words[hard.first_word:hard.last_word]
		for word_index := 0; word_index < len(words); {
			start := words[word_index].start
			best_index := word_index
			// Fit from constant-time prefix widths. Refine the first oversized
			// exponential probe with binary search; unsafe boundaries use shaping.
			probe, step := word_index, 1
			for {
				advance, err := paragraph_line_width(store, font, entry, start, words[probe].end)
				if err != .None { return err }
				if advance > width {
					low, high := best_index + 1, probe
					for low < high {
						mid := low + (high - low) / 2
						w, e := paragraph_line_width(store, font, entry, start, words[mid].end)
						if e != .None { return e }
						if w <= width { best_index, low = mid, mid + 1 } else { high = mid }
					}
					break // An oversized first word remains indivisible.
				}
				best_index = probe
				if probe == len(words) - 1 { break }
				probe = min(len(words) - 1, word_index + step)
				step *= 2
			}
			best := words[best_index].end
			// Reorder cached runs per line, preserving glyph order inside clusters.
			// HarfBuzz-unsafe boundaries retain the exact shaping fallback.
			if !reuse_paragraph_line(store, entry, start, best) {
				if err := reshape_paragraph_line(store, font, entry, start, best); err != .None { return err }
			}
			advance, err := scratch_advance(store)
			if err != .None { return err }
			first := len(store.wrap_infos)
			for &info in store.info_scratch { info.cluster += u32(byte_offset) }
			append(&store.wrap_infos, ..store.info_scratch[:])
			append(&store.wrap_positions, ..store.position_scratch[:])
			append(&store.wrap_lines, Layout_Line{first, len(store.wrap_infos), byte_offset + start, byte_offset + best, advance})
			word_index = best_index + 1
		}
	}
	return .None
}

@(private)
scratch_advance :: proc(store: ^Store) -> (f32, Error) {
	width: f32
	for info, i in store.info_scratch {
		if info.codepoint == 0 { return 0, .Missing_Glyph }
		width += f32(store.position_scratch[i].x_advance) / 64
	}
	return width, .None
}
