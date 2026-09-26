package ui

import "../platform"

// Opens the application's single window and runs its event loop.
// Call once from the main thread. Closing the window exits the process.
// Width and height specify the content size in logical screen points.
open_window :: proc(title: string, width: int = 800, height: int = 600) {
	assert(width > 0 && height > 0, "Window dimensions must be positive")
	platform.open_window(title, width, height)
}
