package text

import "native"
import "core:slice"

// Retain paragraph-level bidi resolution, script runs, and shaped glyphs once
// per text/style. The only predetermined line boundaries are explicit U+2028.
@(private)
prepare_paragraph :: proc(store: ^Store, font: ^Font_Record, entry: ^Paragraph_Entry) -> Error {
	value := entry.key.value
	if len(value) == 0 { return .None }
	store.bidi_calls += 1
	sequence := native.SB_Sequence{encoding = 0, buffer = raw_data(value), length = uintptr(len(value))}
	algorithm := native.SBAlgorithmCreate(&sequence)
	if algorithm == nil { return .Shaping_Failed }
	defer native.SBAlgorithmRelease(algorithm)
	base: u8 = 0xfe
	switch entry.key.direction {
	case .Auto:
	case .LTR: base = 0
	case .RTL: base = 1
	}
	entry.paragraph = native.SBAlgorithmCreateParagraph(algorithm, 0, sequence.length, base)
	if entry.paragraph == nil { return .Shaping_Failed }
	if native.SBParagraphGetLength(entry.paragraph) != sequence.length { return .Unsupported_Text }
	if err := load_scripts(store, &sequence); err != .None { return err }
	select_font_runs(store, value)
	entry.font_runs = make([]Font_Run, len(store.font_runs))
	copy(entry.font_runs, store.font_runs[:])
	entry.scripts = make([]Script_Run, len(store.script_runs))
	copy(entry.scripts, store.script_runs[:])
	entry.prefix = make([]i64, len(value) + 1)
	entry.safe = make([]bool, len(value) + 1)
	segment_start := 0
	for {
		segment_end, next := len(value), len(value) + 1
		for ch, i in value[segment_start:] {
			if ch == '\u2028' { segment_end, next = segment_start + i, segment_start + i + 3; break }
		}
		start, end := segment_start, segment_end
		for start < end && value[start] == ' ' { start += 1 }
		for end > start && value[end - 1] == ' ' { end -= 1 }
		first_word := len(entry.words)
		for at := start; at < end; {
			word_start := at
			for at < end && value[at] != ' ' { at += 1 }
			append(&entry.words, Word_Bounds{word_start, at})
			for at < end && value[at] == ' ' { at += 1 }
		}
		append(&entry.hard_lines, Hard_Line{start, end, first_word, len(entry.words)})
		if start != end {
			line := native.SBParagraphCreateLine(entry.paragraph, uintptr(start), uintptr(end - start))
			if line == nil { return .Shaping_Failed }
			defer native.SBLineRelease(line)
			for bidi in native.SBLineGetRunsPtr(line)[:native.SBLineGetRunCount(line)] {
				bidi_start, bidi_end := int(bidi.offset), int(bidi.offset + bidi.length)
				first := script_at(entry.scripts, bidi_start)
				last := script_at(entry.scripts, bidi_end - 1)
				for i in first..=last {
					script := entry.scripts[i]
					a, b := max(bidi_start, script.start), min(bidi_end, script.end)
					clear(&store.info_scratch)
					clear(&store.position_scratch)
					clear(&store.source_scratch)
					if err := shape_segment(store, font, value, a, b, script.script, bidi.level & 1 != 0, entry.key.language, start, end); err != .None { return err }
					// Prefix widths belong to logical clusters even in RTL runs.
					for info, j in store.info_scratch {
						entry.prefix[int(info.cluster) + 1] += i64(store.position_scratch[j].x_advance)
						entry.safe[info.cluster] = true
					}
					for info in store.info_scratch {
						// hb_glyph_info_get_glyph_flags is this public header macro.
						if info.mask & 1 != 0 { entry.safe[info.cluster] = false }
					}
					glyph_start := len(entry.infos)
					append(&entry.infos, ..store.info_scratch[:])
					append(&entry.positions, ..store.position_scratch[:])
					append(&entry.sources, ..store.source_scratch[:])
					append(&entry.runs, Paragraph_Run{a, b, glyph_start, len(entry.infos), bidi.level & 1 != 0})
				}
			}
		}
		// These are actual text boundaries, not cuts through the cached context.
		entry.safe[start], entry.safe[end] = true, true
		if next > len(value) { break }
		segment_start = next
	}
	for i in 1..<len(entry.prefix) { entry.prefix[i] += entry.prefix[i - 1] }
	slice.sort_by(entry.runs[:], proc(a, b: Paragraph_Run) -> bool { return a.start < b.start })
	return .None
}

@(private)
paragraph_run_at :: proc(runs: []Paragraph_Run, offset: int) -> int {
	low, high := 0, len(runs)
	for low < high {
		mid := low + (high - low) / 2
		if runs[mid].end <= offset { low = mid + 1 } else { high = mid }
	}
	return low
}

// Glyphs inside a run have monotone clusters (descending for RTL). Keep the
// order *inside* clusters unchanged, including marks and multi-glyph clusters.
@(private)
paragraph_glyph_range :: proc(entry: ^Paragraph_Entry, run: Paragraph_Run, start, end: int) -> (int, int) {
	first, last: int
	for pass in 0..<2 {
		boundary := start if pass == 0 else end
		low, high := run.first, run.last
		for low < high {
			mid := low + (high - low) / 2
			cluster := int(entry.infos[mid].cluster)
			before := cluster >= boundary if run.rtl else cluster < boundary
			if before { low = mid + 1 } else { high = mid }
		}
		if pass == 0 { first = low } else { last = low }
	}
	if run.rtl { return last, first }
	return first, last
}

// Copy reusable glyphs in each line's visual run order. Line-specific bidi
// rules can change whitespace/control levels; incompatible slices fall back.
@(private)
reuse_paragraph_line :: proc(store: ^Store, entry: ^Paragraph_Entry, start, end: int) -> bool {
	clear(&store.info_scratch)
	clear(&store.position_scratch)
	clear(&store.source_scratch)
	if !entry.safe[start] || !entry.safe[end] { return false }
	line := native.SBParagraphCreateLine(entry.paragraph, uintptr(start), uintptr(end - start))
	if line == nil { return false }
	defer native.SBLineRelease(line)
	for bidi in native.SBLineGetRunsPtr(line)[:native.SBLineGetRunCount(line)] {
		a, b := int(bidi.offset), int(bidi.offset + bidi.length)
		first := paragraph_run_at(entry.runs[:], a)
		last := paragraph_run_at(entry.runs[:], b - 1)
		rtl := bidi.level & 1 != 0
		for j in 0..<last - first + 1 {
			run := entry.runs[last - j if rtl else first + j]
			if run.rtl != rtl { return false }
			x, y := max(a, run.start), min(b, run.end)
			if (x != run.start && !entry.safe[x]) || (y != run.end && !entry.safe[y]) { return false }
			lo, hi := paragraph_glyph_range(entry, run, x, y)
			append(&store.info_scratch, ..entry.infos[lo:hi])
			append(&store.position_scratch, ..entry.positions[lo:hi])
			append(&store.source_scratch, ..entry.sources[lo:hi])
		}
	}
	return true
}

@(private)
reshape_paragraph_line :: proc(store: ^Store, font: ^Font_Record, entry: ^Paragraph_Entry, start, end: int) -> Error {
	store.wrap_reshapes += 1
	clear(&store.script_runs)
	append(&store.script_runs, ..entry.scripts)
	clear(&store.font_runs)
	append(&store.font_runs, ..entry.font_runs)
	return shape_bidi_line(store, font, entry.key.value, entry.paragraph, start, end, entry.key.language)
}

@(private)
paragraph_line_width :: proc(store: ^Store, font: ^Font_Record, entry: ^Paragraph_Entry, start, end: int) -> (f32, Error) {
	if entry.safe[start] && entry.safe[end] {
		return f32(entry.prefix[end] - entry.prefix[start]) / 64, .None
	}
	if err := reshape_paragraph_line(store, font, entry, start, end); err != .None { return 0, err }
	return scratch_advance(store)
}
