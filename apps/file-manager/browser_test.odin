package file_manager

import "core:testing"
import "../../core/files"
import "core:os"
import "core:path/filepath"
import "core:time"

@(test)
directory_snapshot :: proc(t: ^testing.T) {
	root, err := os.make_directory_temp("", "odin-files-test-*", context.allocator)
	testing.expect(t, err == nil)
	if err != nil { return }
	defer delete(root)
	defer { testing.expect(t, os.remove_all(root) == nil) }
	for name in ([]string{"Zoo", "empty"}) {
		path, _ := filepath.join({root, name})
		testing.expect(t, os.make_directory(path) == nil)
		delete(path)
	}
	for name in ([]string{"b.txt", "A.txt", ".hidden"}) {
		path, _ := filepath.join({root, name})
		testing.expect(t, os.write_entire_file(path, "") == nil)
		delete(path)
	}
	state: Browser
	defer destroy_browser(&state)
	testing.expect(t, read_and_wait(&state, root))
	testing.expect_value(t, len(state.entries), 5)
	testing.expect_value(t, state.folders, 2)
	for name, i in ([5]string{"empty", "Zoo", ".hidden", "A.txt", "b.txt"}) {
		testing.expect_value(t, state.entries[i].info.name, name)
	}
	// A failed open keeps the owned names, path, ordering and identity version.
	generation := state.generation
	missing, _ := filepath.join({root, "missing"})
	defer delete(missing)
	testing.expect(t, !read_and_wait(&state, missing))
	testing.expect_value(t, state.generation, generation)
	testing.expect_value(t, len(state.entries), 5)
	testing.expect_value(t, state.path, root)
	testing.expect(t, state.error != "")
	empty, _ := filepath.join({root, "empty"})
	defer delete(empty)
	testing.expect(t, read_and_wait(&state, empty))
	testing.expect_value(t, state.generation, generation + 1)
	testing.expect_value(t, len(state.entries), 0)
	testing.expect_value(t, state.error, "")
	// Repeated navigation frees every old snapshot and its sorting strings.
	for _ in 0..<8 {
		testing.expect(t, read_and_wait(&state, root))
		testing.expect(t, read_and_wait(&state, empty))
	}
	// Switching twice before polling must discard the superseded navigation.
	browse(&state, root)
	browse(&state, empty)
	testing.expect_value(t, state.state, files.State.Reading)
	wait_for_browser(&state)
	poll_browser(&state)
	testing.expect_value(t, state.path, empty)
	// The active subscription survives a failed navigation, and published
	// snapshots own their names even after cancelled jobs have been disposed.
	testing.expect(t, !read_and_wait(&state, missing))
	added, _ := filepath.join({empty, "new.txt"})
	defer delete(added)
	assert(os.write_entire_file(added, "hello") == nil)
	wait_for_snapshot(&state)
	testing.expect(t, state.refresh && state.error == "")
	testing.expect_value(t, len(state.entries), 1)
	testing.expect_value(t, state.entries[0].info.name, "new.txt")
	assert(os.remove(added) == nil)
	wait_for_snapshot(&state)
	testing.expect_value(t, len(state.entries), 0)
	// A missing initial directory remains subscribed and heals on creation.
	other: Browser
	defer destroy_browser(&other)
	testing.expect_value(t, other.state, files.State.None)
	testing.expect(t, !read_and_wait(&other, missing))
	assert(os.make_directory(missing) == nil)
	wait_for_snapshot(&other)
	testing.expect(t, other.error == "" && other.path == missing)
}

wait_for_snapshot :: proc(state: ^Browser) {
	start := time.tick_now()
	for !poll_browser(state) {
		assert(time.tick_since(start) < 10 * time.Second, "Watch refresh timed out")
		time.sleep(time.Millisecond)
	}
}
