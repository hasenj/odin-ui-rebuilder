package platform

import "../core/primitives"

// An opaque native renderer, owned by the platform's window loop.
Renderer :: distinct rawptr

// Clears the window and draws the complete list in order. Call only from the
// platform's frame loop. An empty list still clears the previous frame.
render :: proc(renderer: Renderer, rectangles: []primitives.Rectangle, size: [2]f32) {
	render_impl(renderer, rectangles, size)
}
