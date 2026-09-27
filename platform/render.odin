package platform

import "../core/primitives"

// An opaque native renderer, owned by the platform's window loop.
Renderer :: distinct rawptr

// Clears the window and draws the complete list in order. Call only from the
// platform's frame loop. An empty list still clears the previous frame.
render :: proc(renderer: Renderer, surfaces: []primitives.Surface, size: [2]f32) {
	render_impl(renderer, surfaces, size)
}

// Physical pixels per logical point, for rasterizing text at the display scale.
pixel_scale :: proc(renderer: Renderer) -> f32 {
	if renderer == nil {
		return 1
	}
	return pixel_scale_impl(renderer)
}
