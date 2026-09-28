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

// Draw one bidi-resolved line at the current rect's top-left. Size is em size in logical
// points. Weight 0 uses the font default; other values select its 'wght' axis.
// Direction controls paragraph reading order, not alignment. Language is a BCP-47
// tag; empty selects ar for Arabic runs, en for Latin, und otherwise.
// Does not consume space, wrap, clip, or discover fallback fonts.
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

// One line, reduced uniformly only as far as min_scale (default 50%). Reports
// overflow if it still exceeds max_width. Uses the desired-size glyph atlas.
layout_text_fit :: proc(value: string, font: Font_Ref, max_width: f32, size: f32 = 16, min_scale: f32 = 0.5, weight: f32 = 0, direction: Text_Direction = .Auto, language: string = "") -> (Text_Layout, Text_Error) {
	frame := current_frame()
	return fonts.fit(&active_state.text, resolve_font(font), value, size, frame.scale, weight, max_width, min_scale, direction, language)
}

// Paint a measured layout into the current rect without consuming it or clipping.
// For a button, use align = .Center, valign = .Center. Reuse with other positions
// and colors freely; widths/heights describe line boxes rather than ink bounds.
draw_text_layout :: proc(layout: Text_Layout, color: Color = {1, 1, 1, 1}, align: Text_Align = .Start, valign: Text_Align = .Start) -> Text_Error {
	frame := current_frame()
	rect := current_rect()
	return fonts.draw_layout(&active_state.text, frame.renderer, layout, rect.position, rect.size, color, &frame.surfaces, align, valign)
}
