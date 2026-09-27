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
