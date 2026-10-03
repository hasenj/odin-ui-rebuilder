package files

import "core:testing"
import "core:os"
import "core:path/filepath"
import "core:time"

@(test)
worker_watch_pipeline :: proc(t: ^testing.T) {
	root, err := os.make_directory_temp("", "odin-file-worker-*", context.allocator)
	assert(err == nil)
	defer delete(root)
	defer { assert(os.remove_all(root) == nil) }
	s := create()
	defer destroy(s)
	testing.expect_value(t, status(s, nil), State.None)
	dir := request(s, root, .Directory)
	initial := await_result(s, dir, 0)
	testing.expect(t, initial.error == "" && len(initial.entries) == 0)
	destroy_result(initial)
	path, _ := filepath.join({root, "photo.png"})
	defer delete(path)
	assert(os.write_entire_file(path, #load("../images/testdata/rgba.png", []u8)) == nil)
	added := await_result(s, dir, 1)
	testing.expect(t, len(added.entries) == 1 && added.entries[0].info.name == "photo.png")
	destroy_result(added)
	img := request(s, path, .Image, max_extent = 1)
	decoded := await_result(s, img, 0)
	testing.expect_value(t, decoded.size, [2]int{1, 1})
	testing.expect_value(t, len(decoded.pixels), 4)
	for value, i in ([]u8{63, 63, 32, 159}) { testing.expect_value(t, decoded.pixels[i], value) }
	destroy_result(decoded)
	// A broken intermediate save publishes an error, then a later write heals.
	assert(os.write_entire_file(path, "not an image") == nil)
	broken := await_result(s, img, 1)
	testing.expect(t, broken.error != "" && len(broken.pixels) == 0)
	destroy_result(broken)
	assert(os.write_entire_file(path, #load("../images/testdata/rgb.jpg", []u8)) == nil)
	healed := await_result(s, img, 2)
	testing.expect(t, healed.error == "" && healed.pixels[3] == 255)
	destroy_result(healed)
	before := revision(s, dir)
	assert(os.remove(path) == nil)
	removed := await_result(s, dir, before)
	testing.expect(t, len(removed.entries) == 0)
	destroy_result(removed)
	// Missing file subscriptions retry after creation, including atomic saves.
	missing := await_result(s, img, 3)
	testing.expect(t, missing.error != "")
	destroy_result(missing)
	assert(os.write_entire_file(path, #load("../images/testdata/rgba.png", []u8)) == nil)
	reappeared := await_result(s, img, 4)
	testing.expect(t, reappeared.error == "")
	retire(s, reappeared)
	// Superseded requests can be released before they start or while running.
	for _ in 0..<128 { release(s, request(s, path, .Image)) }
	release(s, img)
	release(s, dir)
}

await_result :: proc(s: ^Service, task: ^Task, after: u64) -> Result {
	start := time.tick_now()
	for {
		if result, ok := take(s, task); ok {
			if result.revision > after { return result }
			destroy_result(result)
		}
		assert(time.tick_since(start) < 10 * time.Second, "File worker timed out")
		time.sleep(time.Millisecond)
	}
}
