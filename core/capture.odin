package ui

import "../platform"

Capture_Frame :: platform.Capture_Frame
Capture_Error :: platform.Capture_Error
Capture_Result :: platform.Capture_Result

// Drive the ordinary UI builder without opening a window. Identities, fonts,
// images and animations survive between frames in this sequence, then are freed.
// Call outside update, on the main thread. Application-owned state (including
// cached font/image handles) must be initialized for this new capture session;
// handles from another window or capture session must not be reused.
capture_frames :: proc(update: Update, frames: []Capture_Frame) -> Capture_Result {
	assert(active_state == nil, "Cannot start capture inside a UI update")
	state := Frame_State{update = update}
	defer destroy_frame_state(&state)
	return platform.capture_frames(frames, build_frame, &state, &state.frame.input)
}
