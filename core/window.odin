package ui

import "../platform"

Frame_Timing :: platform.Frame_Timing
Window :: platform.Window
Panel :: platform.Panel
close_panel :: platform.close_panel
panel_alive :: platform.window_alive

// Application/window calls run on the main thread. A single event loop drives
// main and its panels. Closing the main window closes all panels and ends run.
init :: platform.init
shutdown :: platform.shutdown
run :: platform.run
window_alive :: platform.window_alive
request_close :: platform.request_close

// Initial dimensions are logical points. OS resizing determines later sizes.
// Fonts, images, identities, focus and scroll state belong to this window.
// Create/close requests inside update are applied after the application cycle.
create_window :: proc(title: string, width: int = 800, height: int = 600, update: Update = nil, frame_timing: Frame_Timing = .Disabled, decorated: bool = true, transparent: bool = ODIN_OS == .Darwin) -> Window {
	state := new(Frame_State)
	state.update = update
	window := platform.create_window(title, width, height, build_frame, state, frame_timing,
		&state.frame.input, decorated, transparent, destroy_window_state)
	state.frame.window = window
	return window
}

// Panels default to borderless and never become native tabs. A closing main
// window rejects creation (zero handle). Resources remain local to each panel.
create_panel :: proc(title: string, width: int = 400, height: int = 300, update: Update = nil, frame_timing: Frame_Timing = .Disabled, decorated: bool = false, transparent: bool = ODIN_OS == .Darwin) -> Panel {
	state := new(Frame_State)
	state.update = update
	panel := platform.create_panel(title, width, height, build_frame, state, frame_timing,
		&state.frame.input, decorated, transparent, destroy_window_state)
	if panel == (Panel{}) { destroy_window_state(state); return {} }
	state.frame.window = panel
	return panel
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
