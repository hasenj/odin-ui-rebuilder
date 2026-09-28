package text

import "core:math"
import "../primitives"
import "../../platform"

// Physical alignment, independent of paragraph reading direction.
Align :: enum {Start, Center, End}

// A lightweight reusable request + measured result, with no caller-owned native
// resources. The input text/language are BORROWED: keep them alive and unchanged
// through drawing. Cached glyphs own their data; eviction never dangles a layout.
// Recreate the result when the text, constraints, or window scale changes.
Layout :: struct {
	width, height, ascent, descent: f32,
	line_count: int,
	size: f32, // Effective em size; fit can reduce it below the requested size.
	overflow: bool, // Width or height exceeds its limit, including at the minimum fit size.
	_request: Layout_Request,
	_divisor: f32,
}

@(private)
Layout_Request :: struct {
	font: Font,
	value, language: string,
	size, scale, weight, wrap_width: f32,
	direction: Direction,
}

// Word wrap, explicit newlines, and per-line bidi. Width is measured advance,
// height is line_count * font line height. Empty text occupies one empty line.
// No rasterization, surface emission, clipping, or layout-space consumption.
layout :: proc(store: ^Store, font: Font, value: string, size, scale, weight, max_width: f32, direction: Direction = .Auto, language: string = "") -> (Layout, Error) {
	if !(max_width >= 0 && !math.is_inf(max_width)) { return {}, .Invalid_Width }
	if !(scale > 0 && scale <= 16) { return {}, .Invalid_Size }
	request := Layout_Request{font, value, language, size, scale, weight, max_width * scale, direction}
	run, err := resolve_layout(store, request)
	if err != .None { return {}, err }
	return layout_result(request, run, scale, size, max_width), .None
}

// Shrink one line to fit both limits; optionally wrap at min_scale if width
// still overflows. Reuses desired-size glyphs throughout. min_scale is in (0, 1].
// Omitted max_height is unconstrained; wrapping is opt-in. Explicit newlines
// remain unsupported: this is a single-line label with a word-wrap fallback.
fit :: proc(store: ^Store, font: Font, value: string, size, scale, weight, max_width: f32, min_scale: f32 = 0.5, direction: Direction = .Auto, language: string = "", max_height: f32 = max(f32), wrap_at_min: bool = false) -> (Layout, Error) {
	if !(max_width >= 0 && !math.is_inf(max_width)) { return {}, .Invalid_Width }
	if !(max_height >= 0 && !math.is_inf(max_height)) { return {}, .Invalid_Height }
	if !(min_scale > 0 && min_scale <= 1) { return {}, .Invalid_Scale }
	if !(scale > 0 && scale <= 16) { return {}, .Invalid_Size }
	request := Layout_Request{font, value, language, size, scale, weight, -1, direction}
	run, err := resolve_layout(store, request)
	if err != .None { return {}, err }
	factor: f32 = 1
	if run.metrics.width > 0 { factor = min(factor, max_width / (run.metrics.width / scale)) }
	if run.metrics.height > 0 { factor = min(factor, max_height / (run.metrics.height / scale)) }
	factor = clamp(factor, min_scale, 1)
	divisor := scale / factor
	if math.is_inf(divisor) { return {}, .Invalid_Scale }
	result := layout_result(request, run, divisor, size * factor, max_width, max_height)
	if wrap_at_min && result.width > max_width + 0.0001 {
		// Wrap in the original physical font coordinates, then scale the whole
		// block. This keeps shaping, paragraph data and atlas sizes reusable.
		request.wrap_width = max_width * divisor
		run, err = resolve_layout(store, request)
		if err != .None { return {}, err }
		result = layout_result(request, run, divisor, size * factor, max_width, max_height)
	}
	return result, .None
}

@(private)
layout_result :: proc(request: Layout_Request, run: Shape, divisor, size, max_width: f32, max_height: f32 = max(f32)) -> Layout {
	m := logical_metrics(run.metrics, divisor)
	return {width = m.width, height = m.height, ascent = m.ascent, descent = m.descent,
		line_count = max(1, len(run.lines)), size = size, overflow = m.width > max_width + 0.0001 || m.height > max_height + 0.0001,
		_request = request, _divisor = divisor}
}

@(private)
resolve_layout :: proc(store: ^Store, request: Layout_Request) -> (Shape, Error) {
	return shape(store, request.font, request.value, request.size * request.scale, request.weight, request.direction, request.language, request.wrap_width)
}

// Reacquiring a cached run is safe even after arbitrary intervening text calls.
// Position/color/alignment do not form part of the shape/geometry cache key.
// Horizontal alignment applies separately to every line in the destination rect.
draw_layout :: proc(store: ^Store, renderer: platform.Renderer, result: Layout, position, bounds: [2]f32, color: primitives.Color, surfaces: ^[dynamic]primitives.Surface, align: Align = .Start, valign: Align = .Start) -> Error {
	run, err := resolve_layout(store, result._request)
	if err != .None { return err }
	if bounds.x <= 0 || bounds.y <= 0 { return .None }
	origin := position
	origin.y += alignment_offset(valign, bounds.y - result.height)
	_, err = draw_shape(store, renderer, run, origin, color, surfaces, result._divisor, bounds.x, align)
	return err
}

@(private)
alignment_offset :: proc(align: Align, extra: f32) -> f32 {
	switch align {
	case .Start: return 0
	case .Center: return extra * 0.5
	case .End: return extra
	}
	return 0
}
