package platform

import "../core/primitives"

// Called on the main thread at a target rate of 60 fps. The returned slice must
// remain valid until the next callback; the platform consumes it immediately.
Frame_Proc :: #type proc(elapsed: f64, size: [2]f32, user_data: rawptr) -> []primitives.Rectangle

// Opens the application's single window and runs the native event loop.
// Call once from the main thread with positive content dimensions in points.
// Closing the window exits the process.
open_window :: proc(title: string, width, height: int, frame: Frame_Proc = nil, user_data: rawptr = nil) {
	open_window_impl(title, width, height, frame, user_data)
}
