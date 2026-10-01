package ui

import "../platform"

Frame_Timing :: platform.Frame_Timing
Window :: platform.Window

// Application/window calls run on the main thread. A single event loop drives
// every window. run returns after the final window closes; shutdown frees all.
init :: platform.init
shutdown :: platform.shutdown
run :: platform.run
window_alive :: platform.window_alive
request_close :: platform.request_close

// Initial dimensions are logical points. OS resizing determines later sizes.
// Fonts, images, identities, focus and scroll state belong to this window.
// Create/close requests inside update are applied after the callback completes.
create_window :: proc(title: string, width: int = 800, height: int = 600, update: Update = nil, frame_timing: Frame_Timing = .Disabled, decorated: bool = true, transparent: bool = ODIN_OS == .Darwin) -> Window {
	state := new(Frame_State)
	state.update = update
	window := platform.create_window(title, width, height, build_frame, state, frame_timing,
		&state.frame.input, decorated, transparent, destroy_window_state)
	state.frame.window = window
	return window
}

current_window :: proc() -> Window {
	return current_frame().window
}

@(private)
destroy_window_state :: proc(data: rawptr) {
	state := cast(^Frame_State)data
	destroy_frame_state(state)
	free(state)
}

// Convenience for a single window. Closing it returns to the caller.
open_window :: proc(title: string, width: int = 800, height: int = 600, update: Update = nil, frame_timing: Frame_Timing = .Disabled, decorated: bool = true, transparent: bool = ODIN_OS == .Darwin) {
	init()
	defer shutdown()
	create_window(title, width, height, update, frame_timing, decorated, transparent)
	run()
}
