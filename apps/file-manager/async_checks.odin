package file_manager

import "../../core/files"
import "core:time"

// Test/capture-only synchronization. The normal update path never waits.
wait_for_browser :: proc(state: ^Browser) {
	start := time.tick_now()
	for state.opening != nil && files.status(state.service, state.opening) == .Reading {
		assert(time.tick_since(start) < 10 * time.Second, "Directory worker timed out")
		time.sleep(time.Millisecond)
	}
}
read_and_wait :: proc(state: ^Browser, path: string) -> bool {
	browse(state, path)
	wait_for_browser(state)
	poll_browser(state)
	return state.error == ""
}
