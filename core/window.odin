package ui

import "../platform"

Frame_Timing :: platform.Frame_Timing

// Opens the application's single window and runs its event loop.
// Call once from the main thread. Closing the window exits the process.
// Width and height specify the content size in logical screen points.
// Frame timing reports callback wall time, update, submit and measured waits.
// GPU execution is not measured separately; submit can include hidden driver stalls.
open_window :: proc(title: string, width: int = 800, height: int = 600, update: Update = nil, frame_timing: Frame_Timing = .Disabled) {
	assert(width > 0 && height > 0, "Window dimensions must be positive")
	state := Frame_State{update = update}
	defer destroy_frame_state(&state)
	platform.open_window(title, width, height, build_frame, &state, frame_timing, &state.frame.input)
}
