package text

import "native"
import c "core:c"
import "core:strings"
import "core:unicode/utf8"

// Create once, then use its name/handle wherever a font is accepted. Stacks are
// immutable and window-owned, so their handle is a complete cache identity.
// Nested stacks are flattened; no face, font file or atlas is duplicated.
font_stack :: proc(store: ^Store, sources: []Font, name: string) -> (Font, Error) {
	if len(sources) == 0 { return 0, .Invalid_Font }
	if _, exists := store.names[name]; name != "" && exists { return 0, .Name_Exists }
	for source in sources { if source == 0 || int(source) > len(store.fonts) { return 0, .Invalid_Font } }
	flat := make([dynamic]Font, context.temp_allocator)
	for source in sources {
		members := store.fonts[int(source) - 1].sources
		if len(members) == 0 { members = []Font{source} }
		for member in members {
			found := false
			for existing in flat { if existing == member { found = true; break } }
			if !found { append(&flat, member) }
		}
	}
	owned := make([]Font, len(flat)); copy(owned, flat[:])
	handle := Font(len(store.fonts) + 1)
	record := Font_Record{handle = handle, sources = owned, name = strings.clone(name)}
	append(&store.fonts, record)
	if name != "" { store.names[record.name] = handle }
	return handle, .None
}

// Static fallbacks use their own normal face; variable fallbacks inherit the
// primary's resolved weight, clamped to their axis. Zero uses their default.
@(private)
source_weight :: proc(font: ^Font_Record, weight: c.long) -> c.long {
	if font.weight_axis < 0 { return 0 }
	axis := font.axes.axis[font.weight_axis]
	return axis.def if weight == 0 else clamp(weight, axis.minimum, axis.maximum)
}

@(private)
font_covers :: proc(store: ^Store, font: ^Font_Record, value: string) -> bool {
	for ch in value {
		// These influence shaping/bidi, not visible character coverage. Keep
		// variation selectors and joiners with their surrounding grapheme.
		if ch == '\u00ad' || ch == '\u034f' || ch == '\u061c' || ch == '\ufeff' ||
		   (ch >= '\u200b' && ch <= '\u200f') || (ch >= '\u202a' && ch <= '\u202e') ||
		   (ch >= '\u2060' && ch <= '\u206f') || (ch >= '\ufe00' && ch <= '\ufe0f') ||
		   (ch >= '\U000e0100' && ch <= '\U000e01ef') { continue }
		covered, known := font.coverage[ch]
		if !known {
			store.coverage_queries += 1
			covered = native.FT_Get_Char_Index(font.face, c.ulong(ch)) != 0
			font.coverage[ch] = covered
		}
		if !covered { return false }
	}
	return true
}

@(private)
choose_font :: proc(store: ^Store, value: string) -> Font {
	for source in store.shaping_sources {
		if font_covers(store, &store.fonts[int(source) - 1], value) { return source }
	}
	return 0
}

@(private)
Font_Run :: struct {start, end: int, font: Font}

// Resolve against the whole paragraph, before wrapping. Line reshaping must
// retain these choices, even if a shorter line could use an earlier font.
@(private)
select_font_runs :: proc(store: ^Store, value: string) {
	clear(&store.font_runs)
	if len(store.shaping_sources) == 0 { return }
	for script in store.script_runs {
		if selected := choose_font(store, value[script.start:script.end]); selected != 0 {
			append(&store.font_runs, Font_Run{script.start, script.end, selected})
			continue
		}
		it := utf8.decode_grapheme_iterator_make(value[script.start:script.end])
		for {
			_, g, ok := utf8.decode_grapheme_iterate(&it); if !ok { break }
			a := script.start + g.byte_index
			b := a + len(g.text)
			selected := choose_font(store, value[a:b])
			if selected == 0 { selected = store.shaping_sources[0] }
			if len(store.font_runs) > 0 && store.font_runs[len(store.font_runs) - 1].font == selected {
				store.font_runs[len(store.font_runs) - 1].end = b
			} else { append(&store.font_runs, Font_Run{a, b, selected}) }
		}
	}
}

@(private)
font_run_at :: proc(runs: []Font_Run, offset: int) -> int {
	lo, hi := 0, len(runs)
	for lo < hi { mid := (lo + hi) / 2; if runs[mid].end <= offset { lo = mid + 1 } else { hi = mid } }
	return lo
}

@(private)
shape_segment :: proc(store: ^Store, primary: ^Font_Record, value: string, start, end: int, script: u32, rtl: bool, language: string, context_start: int = 0, context_end: int = -1) -> Error {
	if len(store.font_runs) == 0 {
		return shape_segment_native(store, primary, value, start, end, script, rtl, language, context_start, context_end)
	}
	first := font_run_at(store.font_runs[:], start)
	last := font_run_at(store.font_runs[:], end - 1)
	for j in 0..<last - first + 1 {
		span := store.font_runs[last - j if rtl else first + j]
		font := &store.fonts[int(span.font) - 1]
		if err := configure_font(font, store.shaping_size, source_weight(font, store.shaping_weight)); err != .None { return err }
		if err := shape_segment_native(store, font, value, max(start, span.start), min(end, span.end), script, rtl, language, context_start, context_end); err != .None { return err }
	}
	return .None
}
