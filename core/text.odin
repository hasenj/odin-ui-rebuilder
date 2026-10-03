package ui

import fonts "text"

Font :: fonts.Font
Font_Ref :: union {Font, string}
Text_Metrics :: fonts.Metrics
Text_Error :: fonts.Error
Text_Direction :: fonts.Direction

// Load once during update. The font remains owned by this window until it closes.
// Optional name registers an application alias; otherwise use the family name.
load_font :: proc(path: string, name: string = "", face_index: int = 0) -> (Font, Text_Error) {
	_ = current_frame()
	return fonts.load(&active_state.text, path, name, face_index)
}

find_font :: proc(name: string) -> (Font, bool) {
	_ = current_frame()
	return fonts.find(&active_state.text, name)
}

// Register an immutable fallback order once; use its name/handle for drawing,
// measurement, wrapping, local layout or editing. Font files remain shared.
font_stack :: proc(name: string, sources: []Font_Ref) -> (Font, Text_Error) {
	_ = current_frame()
	handles := make([]Font, len(sources), context.temp_allocator)
	for source, i in sources { handles[i] = resolve_font(source) }
	return fonts.font_stack(&active_state.text, handles, name)
}

// Draw one bidi-resolved line at the current rect's top-left. Size is em size in logical
// points. Weight 0 uses the font default; other values select its 'wght' axis.
// Direction controls paragraph reading order, not alignment. Language is a BCP-47
// tag; empty selects ar for Arabic runs, en for Latin, und otherwise.
// Does not consume space, wrap or clip. A font stack provides explicit fallbacks.
// Empty rects emit nothing, but still return the same metrics/errors as measurement.
text :: proc(value: string, font: Font_Ref, size: f32 = 16, color: Color = {1, 1, 1, 1}, weight: f32 = 0, direction: Text_Direction = .Auto, language: string = "") -> (Text_Metrics, Text_Error) {
	frame := current_frame()
	handle := resolve_font(font)
	rect := current_rect()
	if rect.size.x == 0 || rect.size.y == 0 {
		return fonts.measure(&active_state.text, handle, value, size, frame.scale, weight, direction, language)
	}
	return fonts.draw(&active_state.text, frame.renderer, handle, value, size, frame.scale, weight,
		rect.position, color, &frame.surfaces, direction, language)
}

// Same shaping/metrics as text(), without rasterizing or emitting any surfaces.
// Width is advance width (includes spaces), not a tight bounding box of the ink.
measure_text :: proc(value: string, font: Font_Ref, size: f32 = 16, weight: f32 = 0, direction: Text_Direction = .Auto, language: string = "") -> (Text_Metrics, Text_Error) {
	frame := current_frame()
	return fonts.measure(&active_state.text, resolve_font(font), value, size, frame.scale, weight, direction, language)
}

@(private)
resolve_font :: proc(ref: Font_Ref) -> Font {
	switch value in ref {
	case Font: return value
	case string:
		font, _ := fonts.find(&active_state.text, value)
		return font
	}
	return 0
}

Text_Layout :: fonts.Layout
Text_Align :: fonts.Align // Start/End mean left/right or top/bottom, irrespective of bidi.

// Measure and cache word-wrapped text. Breaks at ASCII spaces and explicit
// newlines; overlong words remain intact and set overflow. No hyphenation yet.
// Text/language storage must remain alive and unchanged until drawing completes.
// Call again when constraints or window scale change; unchanged calls are cached.
layout_text :: proc(value: string, font: Font_Ref, max_width: f32, size: f32 = 16, weight: f32 = 0, direction: Text_Direction = .Auto, language: string = "") -> (Text_Layout, Text_Error) {
	frame := current_frame()
	return fonts.layout(&active_state.text, resolve_font(font), value, size, frame.scale, weight, max_width, direction, language)
}

// Shrink one line to fit width and optional height, stopping at min_scale (50%).
// With wrap_at_min, wrap words if the minimum-size line still exceeds the width.
// Reports overflow if either limit is still exceeded. No clipping or truncation.
// Uses the desired-size glyph atlas; newlines remain unsupported.
layout_text_fit :: proc(value: string, font: Font_Ref, max_width: f32, size: f32 = 16, min_scale: f32 = 0.5, weight: f32 = 0, direction: Text_Direction = .Auto, language: string = "", max_height: f32 = max(f32), wrap_at_min: bool = false) -> (Text_Layout, Text_Error) {
	frame := current_frame()
	return fonts.fit(&active_state.text, resolve_font(font), value, size, frame.scale, weight, max_width, min_scale, direction, language, max_height, wrap_at_min)
}

// Paint a measured layout without consuming space. Active renderer clips apply;
// the current rect itself does not implicitly clip the layout.
// For a button, use align = .Center, valign = .Center. Reuse with other positions
// and colors freely; widths/heights describe line boxes rather than ink bounds.
draw_text_layout :: proc(layout: Text_Layout, color: Color = {1, 1, 1, 1}, align: Text_Align = .Start, valign: Text_Align = .Start) -> Text_Error {
	frame := current_frame()
	rect := current_rect()
	return fonts.draw_layout(&active_state.text, frame.renderer, layout, rect.position, rect.size, color, &frame.surfaces, align, valign)
}

Text_Caret_Span :: fonts.Caret_Span

// Caller-owned single-line grapheme geometry for building custom editors.
// leading/trailing are visual X coordinates relative to the rendered origin;
// start/end are logical UTF-8 bytes. A logical selection can have disjoint spans.
// Rebuild when text/font/style/scale changes; retain the result between frames.
text_caret_spans :: proc(value: string, font: Font_Ref, spans: ^[dynamic]Text_Caret_Span, size: f32 = 16, weight: f32 = 0, direction: Text_Direction = .Auto, language: string = "") -> (Text_Metrics, Text_Error) {
	frame := current_frame()
	return fonts.caret_spans(&active_state.text, resolve_font(font), value, size, frame.scale, weight, spans, direction, language)
}

// Nearest visual caret edge. Retain X as affinity: at a bidi boundary one byte
// offset can have two visual positions. Empty geometry returns the line start.
text_hit_test :: proc(spans: []Text_Caret_Span, x: f32) -> (byte: int, position: f32) {
	best: f32 = max(f32)
	for span in spans {
		for edge in ([2]struct {index: int, x: f32}{{span.start, span.leading}, {span.end, span.trailing}}) {
			distance := abs(x - edge.x)
			if distance < best { byte, position, best = edge.index, edge.x, distance }
		}
	}
	return
}
