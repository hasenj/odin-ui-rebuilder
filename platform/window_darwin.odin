package platform

import "darwin"

// Odin selects this implementation by the _darwin file suffix.
open_window :: proc(title: string, width, height: int) {
	darwin.open_window(title, width, height)
}
