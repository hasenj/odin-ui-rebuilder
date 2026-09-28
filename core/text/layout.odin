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
	overflow: bool, // Advance width exceeds max_width (unbreakable word or minimum fit size).
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

// Single line, uniformly scaled to fit its advance width. Reuses desired-size
// glyphs, including during continuous resizing; never populates the atlas with
// a separate bitmap size for every intermediate width. min_scale is in (0, 1].
fit :: proc(store: ^Store, font: Font, value: string, size, scale, weight, max_width: f32, min_scale: f32 = 0.5, direction: Direction = .Auto, language: string = "") -> (Layout, Error) {
	if !(max_width >= 0 && !math.is_inf(max_width)) { return {}, .Invalid_Width }
	if !(min_scale > 0 && min_scale <= 1) { return {}, .Invalid_Scale }
	if !(scale > 0 && scale <= 16) { return {}, .Invalid_Size }
	request := Layout_Request{font, value, language, size, scale, weight, -1, direction}
	run, err := resolve_layout(store, request)
	if err != .None { return {}, err }
	factor: f32 = 1
	if run.metrics.width > 0 { factor = clamp(max_width / (run.metrics.width / scale), min_scale, 1) }
	return layout_result(request, run, scale / factor, size * factor, max_width), .None
}

@(private)
layout_result :: proc(request: Layout_Request, run: Shape, divisor, size, max_width: f32) -> Layout {
	m := logical_metrics(run.metrics, divisor)
	return {width = m.width, height = m.height, ascent = m.ascent, descent = m.descent,
		line_count = max(1, len(run.lines)), size = size, overflow = m.width > max_width + 0.0001,
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
