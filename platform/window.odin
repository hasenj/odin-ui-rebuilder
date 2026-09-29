package platform

import "../core/primitives"
import "../core/input"

// Called on the main thread at a target rate of 60 fps. The returned slice must
// remain valid until the next callback; the platform consumes it immediately.
Frame_Proc :: #type proc(renderer: Renderer, elapsed: f64, size: [2]f32, user_data: rawptr) -> []primitives.Surface

// Opens the application's single window and runs the native event loop.
// Call once from the main thread with positive content dimensions in points.
// Closing the window exits the process.
// If supplied, input_state must live for the window's lifetime. The platform
// overwrites it on the main thread before each frame callback.
// macOS supports independent decoration/transparency options. Transparency
// defaults on there; Linux keeps its existing decorated, opaque behavior.
open_window :: proc(title: string, width, height: int, frame: Frame_Proc = nil, user_data: rawptr = nil, frame_timing: Frame_Timing = .Disabled, input_state: ^input.State = nil, decorated: bool = true, transparent: bool = ODIN_OS == .Darwin) {
	open_window_impl(title, width, height, frame, user_data, frame_timing, input_state, decorated, transparent)
}
