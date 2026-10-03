package ui

import "files"
import "core:testing"
import "core:os"
import "core:path/filepath"
import "core:time"
import "core:fmt"
import "core:image/png"
import "core:image"
import "core:slice"

@(private) file_image_path: string
@(private) file_image_stage: int
@(private) file_image_original: Image

// Sequentially invoked by the frame pipeline: worker -> main-thread GPU upload
// -> real Metal rendering -> independently decoded captures. No user files.
@(private)
image_file_pipeline :: proc(t: ^testing.T) {
	root, err := os.make_directory_temp("", "odin-image-cache-*", context.allocator)
	assert(err == nil)
	defer delete(root)
	defer { assert(os.remove_all(root) == nil) }
	file_image_path, _ = filepath.join({root, "watched.png"})
	defer delete(file_image_path)
	assert(os.write_entire_file(file_image_path, #load("images/testdata/rgba.png", []u8)) == nil)
	paths: [3]string
	for &path, i in paths { path = fmt.aprintf("%s/capture-%d.png", root, i) }
	defer for path in paths { delete(path) }
	file_image_stage = 0
	file_image_original = {}
	frames := [?]Capture_Frame{
		{size = {40, 40}, scale = 1},
		{size = {40, 40}, scale = 1, path = paths[0]},
		{size = {40, 40}, scale = 1, path = paths[1]},
		{size = {40, 40}, scale = 1, path = paths[2]},
		{size = {40, 40}, scale = 1},
	}
	result := capture_frames(image_file_scene, frames[:])
	testing.expect_value(t, result.error, Capture_Error.None)
	testing.expect_value(t, file_image_stage, len(frames))
	original, e0 := png.load(paths[0])
	preserved, e1 := png.load(paths[1])
	reloaded, e2 := png.load(paths[2])
	assert(e0 == nil && e1 == nil && e2 == nil)
	defer image.destroy(original)
	defer image.destroy(preserved)
	defer image.destroy(reloaded)
	testing.expect(t, slice.equal(original.pixels.buf[:], preserved.pixels.buf[:]))
	testing.expect(t, !slice.equal(original.pixels.buf[:], reloaded.pixels.buf[:]))
	// Top-left of the first PNG fixture is opaque red.
	p := (5 * 40 + 5) * 4
	for value, i in ([4]u8{255, 0, 0, 255}) {
		testing.expect_value(t, original.pixels.buf[p + i], value)
	}
}

@(private)
image_file_scene :: proc() {
	defer { file_image_stage += 1 }
	if file_image_stage == 4 {
		// LRU eviction releases the old GPU handle. Current-frame uses are
		// pinned so later calls cannot invalidate already emitted surfaces.
		for i in 0..<128 {
			path := fmt.aprintf("%s-missing-%d", file_image_path, i)
			image_file(path, watch = false)
			delete(path)
		}
		assert(len(active_state.image_files.records) == 128)
		_, valid := image_size(file_image_original)
		assert(!valid)
		full := image_file(file_image_path)
		assert(full.error != "" && full.image == (Image{}))
		return
	}
	loaded := paint_image(file_image_path)
	switch file_image_stage {
	case 0:
		wait_for_image_revision(1)
	case 1:
		assert(loaded.image != (Image{}) && loaded.state == .Done && loaded.error == "")
		file_image_original = loaded.image
		assert(os.write_entire_file(file_image_path, "broken") == nil)
		wait_for_image_revision(2)
		// Completion in the middle of a frame cannot replace an emitted image.
		again := image_file(file_image_path)
		assert(again.image == loaded.image && again.error == "")
	case 2:
		assert(loaded.image == file_image_original && loaded.error != "")
		assert(os.write_entire_file(file_image_path, #load("images/testdata/rgb.jpg", []u8)) == nil)
		wait_for_image_revision(3)
	case 3:
		assert(loaded.error == "" && loaded.image != file_image_original)
		_, valid := image_size(file_image_original)
		assert(!valid)
	}
}

// Tests only; the public helpers and application never wait for workers.
@(private)
wait_for_image_revision :: proc(wanted: u64) {
	store := &active_state.image_files
	record := store.records[Image_File_Key{path = file_image_path, watch = true}]
	start := time.tick_now()
	for files.revision(store.service, record.task) < wanted {
		assert(time.tick_since(start) < 10 * time.Second, "Image worker timed out")
		time.sleep(time.Millisecond)
	}
}
