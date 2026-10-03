package platform

import "core:math"
import "../core/input"
import "../core/primitives"

// One deterministic update. Empty path advances UI state without saving a PNG.
// Sizes are logical points; ceil(size * scale) gives the PNG pixel dimensions.
Capture_Frame :: struct {
	path: string,
	size: [2]f32,
	scale: f32, // Required, normally 1 or 2.
	time: f64,
	input: input.State,
	clear_color: primitives.Color, // Straight RGBA; transparent by default.
}

Capture_Error :: enum {None, Unsupported, Invalid_Frame, Render_Failed, Write_Failed}

Capture_Result :: struct {
	error: Capture_Error,
	frame_index: int, // Zero-based failing frame; -1 on success / setup failure.
}

// Creates a private renderer, runs the sequence synchronously, then releases all
// GPU resources. No native window or event loop. Implemented on Metal and GLES.
// Frame callbacks have the same lifetime rules as window callbacks. Each saved
// frame waits for GPU completion. Paths are overwritten; directories must exist.
capture_frames :: proc(frames: []Capture_Frame, frame: Frame_Proc, user_data: rawptr = nil, input_state: ^input.State = nil) -> Capture_Result {
	for item, i in frames {
		if !valid_capture_frame(item) || (i > 0 && item.time < frames[i - 1].time) {
			return {.Invalid_Frame, i}
		}
	}
	if len(frames) == 0 { return {frame_index = -1} }
	when ODIN_OS == .Darwin || ODIN_OS == .Linux {
		return capture_frames_impl(frames, frame, user_data, input_state)
	} else {
		return {error = .Unsupported, frame_index = -1}
	}
}

@(private)
valid_capture_frame :: proc(item: Capture_Frame) -> bool {
	if !(item.scale > 0) || math.is_inf(item.scale) ||
	   !(item.time >= 0) || math.is_inf(item.time) { return false }
	for length in item.size {
		pixels := f64(length) * f64(item.scale)
		if !(pixels > 0 && pixels <= 16384) { return false }
	}
	for component in item.clear_color {
		if !(component >= 0 && component <= 1) { return false }
	}
	return true
}
