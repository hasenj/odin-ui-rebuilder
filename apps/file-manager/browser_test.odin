package file_manager

import "core:testing"
import "core:os"
import "core:path/filepath"

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
	testing.expect(t, browse(&state, root))
	testing.expect_value(t, len(state.entries), 5)
	testing.expect_value(t, state.folders, 2)
	for name, i in ([5]string{"empty", "Zoo", ".hidden", "A.txt", "b.txt"}) {
		testing.expect_value(t, state.entries[i].info.name, name)
	}
	// A failed open keeps the owned names, path, ordering and identity version.
	generation := state.generation
	missing, _ := filepath.join({root, "missing"})
	defer delete(missing)
	testing.expect(t, !browse(&state, missing))
	testing.expect_value(t, state.generation, generation)
	testing.expect_value(t, len(state.entries), 5)
	testing.expect_value(t, state.path, root)
	testing.expect(t, state.error != "")
	empty, _ := filepath.join({root, "empty"})
	defer delete(empty)
	testing.expect(t, browse(&state, empty))
	testing.expect_value(t, state.generation, generation + 1)
	testing.expect_value(t, len(state.entries), 0)
	testing.expect_value(t, state.error, "")
	// Repeated navigation frees every old snapshot and its sorting strings.
	for _ in 0..<8 {
		testing.expect(t, browse(&state, root))
		testing.expect(t, browse(&state, empty))
	}
}
