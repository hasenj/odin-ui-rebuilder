package text

import "native"

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
shape_wrapped :: proc(store: ^Store, run: ^Shape, value: string, width: f32, direction: Direction, language: string) -> Error {
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
		if err := wrap_paragraph(store, run.font, value[start:end], start, width, direction, language); err != .None { return err }
		if next > len(value) { break }
		start = next
	}
	run.infos, run.positions, run.lines = store.wrap_infos[:], store.wrap_positions[:], store.wrap_lines[:]
	for line in run.lines { run.metrics.width = max(run.metrics.width, line.width) }
	run.metrics.height = run.line_height * f32(len(run.lines))
	return .None
}

@(private)
wrap_paragraph :: proc(store: ^Store, font: ^Font_Record, value: string, byte_offset: int, width: f32, direction: Direction, language: string) -> Error {
	if len(value) == 0 {
		append(&store.wrap_lines, Layout_Line{start = len(store.wrap_infos), end = len(store.wrap_infos), byte_start = byte_offset, byte_end = byte_offset})
		return .None
	}
	store.bidi_calls += 1
	sequence := native.SB_Sequence{encoding = 0, buffer = raw_data(value), length = uintptr(len(value))}
	algorithm := native.SBAlgorithmCreate(&sequence)
	if algorithm == nil { return .Shaping_Failed }
	defer native.SBAlgorithmRelease(algorithm)
	base: u8 = 0xfe
	switch direction {
	case .Auto:
	case .LTR: base = 0
	case .RTL: base = 1
	}
	paragraph := native.SBAlgorithmCreateParagraph(algorithm, 0, sequence.length, base)
	if paragraph == nil { return .Shaping_Failed }
	defer native.SBParagraphRelease(paragraph)
	if native.SBParagraphGetLength(paragraph) != sequence.length { return .Unsupported_Text }
	if err := load_scripts(store, &sequence); err != .None { return err }
	// U+2028 forces a line break without changing paragraph bidi context.
	segment_start := 0
	for {
		segment_end, next := len(value), len(value) + 1
		for ch, i in value[segment_start:] {
			if ch == '\u2028' {
				segment_end, next = segment_start + i, segment_start + i + 3
				break
			}
		}
		start, end := segment_start, segment_end
		for start < end && value[start] == ' ' { start += 1 }
		for end > start && value[end - 1] == ' ' { end -= 1 }
		if start == end {
			append(&store.wrap_lines, Layout_Line{start = len(store.wrap_infos), end = len(store.wrap_infos), byte_start = byte_offset + start, byte_end = byte_offset + end})
		}
		clear(&store.wrap_words)
		for at := start; at < end; {
			word_start := at
			for at < end && value[at] != ' ' { at += 1 }
			append(&store.wrap_words, Word_Bounds{word_start, at})
			for at < end && value[at] == ' ' { at += 1 }
		}
		words := store.wrap_words[:]
		for word_index := 0; word_index < len(words); {
			start = words[word_index].start
			best_index := word_index
			// Exponential probing avoids shaping every growing word prefix of a
			// wide paragraph. Refine the first oversized probe with binary search.
			probe, step := word_index, 1
			for {
				advance, err := measure_bidi_line(store, font, value, paragraph, start, words[probe].end, language)
				if err != .None { return err }
				if advance > width {
					low, high := best_index + 1, probe
					for low < high {
						mid := low + (high - low) / 2
						w, e := measure_bidi_line(store, font, value, paragraph, start, words[mid].end, language)
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
			// Shape exactly the selected line, retaining paragraph levels but no
			// shaping context across its edges. Never reuse a mid-word glyph cut.
			if err := shape_bidi_line(store, font, value, paragraph, start, best, language); err != .None { return err }
			advance, err := scratch_advance(store)
			if err != .None { return err }
			first := len(store.wrap_infos)
			for &info in store.info_scratch { info.cluster += u32(byte_offset) }
			append(&store.wrap_infos, ..store.info_scratch[:])
			append(&store.wrap_positions, ..store.position_scratch[:])
			append(&store.wrap_lines, Layout_Line{first, len(store.wrap_infos), byte_offset + start, byte_offset + best, advance})
			word_index = best_index + 1
		}
		if next > len(value) { break }
		segment_start = next
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

@(private)
measure_bidi_line :: proc(store: ^Store, font: ^Font_Record, value: string, paragraph: native.SB_Paragraph, start, end: int, language: string) -> (f32, Error) {
	if err := shape_bidi_line(store, font, value, paragraph, start, end, language); err != .None { return 0, err }
	return scratch_advance(store)
}
