package text

import "native"
import c "core:c"

@(private)
Script_Run :: struct {start, end: int, script: u32}

// Resolve a single paragraph/line, intersect bidi and script runs, then shape
// each intersection in logical source order. Append the results in visual order.
// HarfBuzz performs glyph mirroring for RTL runs; never mirror the source twice.
@(private)
shape_line :: proc(store: ^Store, font: ^Font_Record, value: string, direction: Direction, language: string) -> Error {
	clear(&store.info_scratch)
	clear(&store.position_scratch)
	clear(&store.script_runs)
	if len(value) == 0 { return .None }
	store.bidi_calls += 1
	sequence := native.SB_Sequence{encoding = 0, buffer = raw_data(value), length = uintptr(len(value))}
	algorithm := native.SBAlgorithmCreate(&sequence)
	if algorithm == nil { return .Shaping_Failed }
	defer native.SBAlgorithmRelease(algorithm)
	base: u8 = 0xfe // Auto, with LTR fallback when there are no strong characters.
	switch direction {
	case .Auto:
	case .LTR: base = 0
	case .RTL: base = 1
	}
	paragraph := native.SBAlgorithmCreateParagraph(algorithm, 0, sequence.length, base)
	if paragraph == nil { return .Shaping_Failed }
	defer native.SBParagraphRelease(paragraph)
	// Other Unicode paragraph separators must not silently truncate the string.
	if native.SBParagraphGetLength(paragraph) != sequence.length { return .Unsupported_Text }
	line := native.SBParagraphCreateLine(paragraph, 0, sequence.length)
	if line == nil { return .Shaping_Failed }
	defer native.SBLineRelease(line)
	if store.script_locator == nil {
		store.script_locator = native.SBScriptLocatorCreate()
		if store.script_locator == nil { return .Shaping_Failed }
	}
	native.SBScriptLocatorLoadCodepoints(store.script_locator, &sequence)
	for native.SBScriptLocatorMoveNext(store.script_locator) != 0 {
		agent := native.SBScriptLocatorGetAgent(store.script_locator)
		append(&store.script_runs, Script_Run{int(agent.offset), int(agent.offset + agent.length), native.SBScriptGetUnicodeTag(agent.script)})
	}
	if len(store.script_runs) == 0 { return .Shaping_Failed }
	// SheenBidi's line runs are already ordered left-to-right on the display.
	for bidi in native.SBLineGetRunsPtr(line)[:native.SBLineGetRunCount(line)] {
		start, end := int(bidi.offset), int(bidi.offset + bidi.length)
		first := script_at(store.script_runs[:], start)
		last := script_at(store.script_runs[:], end - 1)
		rtl := bidi.level & 1 != 0
		for j in 0..<last - first + 1 {
			i := last - j if rtl else first + j
			script := store.script_runs[i]
			err := shape_segment(store, font, value, max(start, script.start), min(end, script.end), script.script, rtl, language)
			if err != .None { return err }
		}
	}
	return .None
}

@(private)
script_at :: proc(runs: []Script_Run, offset: int) -> int {
	low, high := 0, len(runs)
	for low < high {
		mid := low + (high - low) / 2
		if runs[mid].end <= offset { low = mid + 1 } else { high = mid }
	}
	assert(low < len(runs))
	return low
}

@(private)
shape_segment :: proc(store: ^Store, font: ^Font_Record, value: string, start, end: int, script: u32, rtl: bool, language: string) -> Error {
	buffer := store.buffer
	native.hb_buffer_clear_contents(buffer)
	// Keep the full logical string as context, and byte clusters relative to it.
	native.hb_buffer_add_utf8(buffer, raw_data(value), c.int(len(value)), c.uint(start), c.int(end - start))
	native.hb_buffer_set_direction(buffer, 5 if rtl else 4)
	native.hb_buffer_set_script(buffer, script)
	lang := language
	if lang == "" {
		switch script {
		case 0x41726162: lang = "ar" // Arab
		case 0x4c61746e: lang = "en" // Latn
		case: lang = "und"
		}
	}
	native.hb_buffer_set_language(buffer, native.hb_language_from_string(cstring(raw_data(lang)), c.int(len(lang))))
	// Formatting controls influence bidi/shaping but must not emit glyphs.
	flags: u32 = 8 // HB_BUFFER_FLAG_REMOVE_DEFAULT_IGNORABLES
	if start == 0 { flags |= 1 } // BOT
	if end == len(value) { flags |= 2 } // EOT
	native.hb_buffer_set_flags(buffer, flags)
	store.shape_calls += 1
	native.hb_shape(font.hb, buffer, nil, 0)
	if native.hb_buffer_allocation_successful(buffer) == 0 { return .Shaping_Failed }
	count := native.hb_buffer_get_length(buffer)
	infos := native.hb_buffer_get_glyph_infos(buffer, nil)[:count]
	positions := native.hb_buffer_get_glyph_positions(buffer, nil)[:count]
	append(&store.info_scratch, ..infos)
	append(&store.position_scratch, ..positions)
	return .None
}
