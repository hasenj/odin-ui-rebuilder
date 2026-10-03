package file_manager

import ui "../../core"
import "core:fmt"
import "core:os"
import "core:path/filepath"

capture_root: string
capture_step: int

// Real temporary directories plus synthetic input exercise the same browser
// and builder as the window. Never enumerate or alter the user's files here.
capture_check :: proc() {
	root, err := os.make_directory_temp("", "odin-files-*", context.allocator)
	assert(err == nil)
	defer delete(root)
	defer { assert(os.remove_all(root) == nil) }
	capture_root = root
	for name in ([]string{"Documents", "Empty", "Photos"}) {
		path, _ := filepath.join({root, name})
		assert(os.make_directory(path) == nil)
		delete(path)
	}
	for name in ([]string{"Documents/Project notes.txt", "A note.txt", "B-旅.txt", "C\nlinebreak.txt", "Z-a very long filename that extends beyond the available row width.txt"}) {
		path, _ := filepath.join({root, name})
		assert(os.write_entire_file(path, "Sample file.\n") == nil)
		delete(path)
	}
	for i in 0..<30 {
		path := fmt.aprintf("%s/Sample %02d.txt", root, i + 1)
		assert(os.write_entire_file(path, "Sample file.\n") == nil)
		delete(path)
	}
	browser.initialized = true
	assert(browse(&browser, root))
	assert(browser.folders == 3 && len(browser.entries) == 37)
	assert(browser.entries[0].info.name == "Documents" && browser.entries[1].info.name == "Empty")
	frames := [?]ui.Capture_Frame{
		{path = "bin/file-manager-files.png"},
		{input = {mouse_inside = true, mouse_position = {150, 128}, mouse_buttons = {.Left}}},
		{input = {mouse_inside = true, mouse_position = {150, 128}}},
		{path = "bin/file-manager-folder.png"},
		{input = {mouse_inside = true, mouse_position = {50, 43}, mouse_buttons = {.Left}}},
		{input = {mouse_inside = true, mouse_position = {50, 43}}},
		{},
		{path = "bin/file-manager-scrolled.png", input = {mouse_inside = true, mouse_position = {200, 200}, scroll_delta = {0, 1200}}},
		{input = {mouse_inside = true, mouse_position = {200, 200}, scroll_delta = {0, -1200}}},
		{input = {mouse_inside = true, mouse_position = {150, 168}, mouse_buttons = {.Left}}},
		{input = {mouse_inside = true, mouse_position = {150, 168}}},
		{path = "bin/file-manager-empty.png"},
		{},
		{input = {mouse_inside = true, mouse_position = {150, 248}, mouse_buttons = {.Left}}},
		{input = {mouse_inside = true, mouse_position = {150, 248}}},
		{},
		{path = "bin/file-manager-error.png"},
		{path = "bin/file-manager-narrow.png", size = {360, 320}, scale = 1},
	}
	for &frame, i in frames {
		if frame.size == ([2]f32{}) { frame.size = {780, 640}; frame.scale = 2 }
		frame.time = f64(i) * 0.1
	}
	result := ui.capture_frames(capture_update, frames[:])
	assert(result.error == .None)
	assert(capture_step == len(frames))
	assert(browser.reads == 6, "Only navigation should read the directory")
	fmt.println("Verified file browser: folder ordering, click navigation, Up, scrolling, empty/error states and inert files")
}

capture_update :: proc() {
	if capture_step == 12 { queue_directory(&browser, capture_root) }
	if capture_step == 16 {
		path, _ := filepath.join({capture_root, "No longer here"})
		queue_directory(&browser, path)
		delete(path)
	}
	update()
	switch capture_step {
	case 3:
		assert(filepath.base(browser.path) == "Documents" && len(browser.entries) == 1)
		assert(last_scroll == 0)
	case 6:
		assert(browser.path == capture_root && last_scroll == 0)
	case 7: assert(last_scroll > 0)
	case 8: assert(last_scroll == 0)
	case 11:
		assert(filepath.base(browser.path) == "Empty" && len(browser.entries) == 0 && last_scroll == 0)
	case 15:
		assert(browser.path == capture_root && browser.pending == "", "Clicking a file must do nothing")
	case 16:
		assert(browser.path == capture_root && browser.error != "" && len(browser.entries) == 37)
	}
	capture_step += 1
}
