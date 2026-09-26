package ui

import "../platform"

Frame_Timing :: platform.Frame_Timing

// Opens the application's single window and runs its event loop.
// Call once from the main thread. Closing the window exits the process.
// Width and height specify the content size in logical screen points.
// Frame timing reports CPU wall time to stdout; GPU execution is not included.
open_window :: proc(title: string, width: int = 800, height: int = 600, update: Update = nil, frame_timing: Frame_Timing = .Disabled) {
	assert(width > 0 && height > 0, "Window dimensions must be positive")
	state := Frame_State{update = update}
	defer delete(state.frame.rectangles)
	platform.open_window(title, width, height, build_frame, &state, frame_timing, &state.frame.input)
}
