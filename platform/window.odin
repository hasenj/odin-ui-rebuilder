package platform

// Opens the application's single window and runs the native event loop.
// Call once from the main thread with positive content dimensions in points.
// Closing the window exits the process.
open_window :: proc(title: string, width, height: int) {
	open_window_impl(title, width, height)
}
