package platform

import "../core/primitives"
import "core:time"

// An opaque native renderer, owned by the platform's window loop.
Renderer :: distinct rawptr

// Wall-clock durations, not active CPU time. Waits covers entire potentially
// blocking drawable/scheduling/presentation calls, including their API overhead.
// Hidden stalls inside other driver calls can still appear under submit.
Render_Timing :: struct {submit_ms, waits_ms: f64}

// Clears the window and draws the complete list in order. Call only from the
// platform's frame loop. An empty list still clears the previous frame.
render :: proc(renderer: Renderer, surfaces: []primitives.Surface, size: [2]f32, timing: ^Render_Timing = nil) {
	start: time.Tick
	if timing != nil {
		timing^ = {}
		start = time.tick_now()
	}
	render_impl(renderer, surfaces, size, timing)
	if timing != nil {
		total := time.duration_milliseconds(time.tick_since(start))
		timing.submit_ms = max(0, total - timing.waits_ms)
	}
}

// No clock reads when profiling is disabled. Backend scopes must not overlap.
@(private)
render_wait_begin :: proc(timing: ^Render_Timing) -> time.Tick {
	if timing != nil { return time.tick_now() }
	return {}
}

@(private)
render_wait_end :: proc(timing: ^Render_Timing, start: time.Tick) {
	if timing != nil { timing.waits_ms += time.duration_milliseconds(time.tick_since(start)) }
}

// Physical pixels per logical point, for rasterizing text at the display scale.
pixel_scale :: proc(renderer: Renderer) -> f32 {
	if renderer == nil {
		return 1
	}
	return pixel_scale_impl(renderer)
}
