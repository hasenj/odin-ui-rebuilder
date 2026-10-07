package file_manager

import ui "../../core"
import "../../core/files"
import "core:os"
import "core:path/filepath"
import "core:fmt"
import "core:time"

@(private) design_step: int
@(private) design_root: string
@(private) design_focus: ui.Identity

// Deterministic design evidence and live refresh checks, using temporary files.
capture_design :: proc() {
	destroy_browser(&browser)
	destroy_list()
	font, previous, pressed_id = 0, {}, {}
	root, err := os.make_directory_temp("", "odin-files-design-*", context.allocator)
	assert(err == nil)
	defer delete(root)
	defer { assert(os.remove_all(root) == nil) }
	design_root, _ = filepath.join({root, "Downloads"})
	defer delete(design_root)
	assert(os.make_directory(design_root) == nil)
	for name in ([]string{"Photos", "Projects"}) {
		path := fmt.aprintf("%s/%s", design_root, name)
		assert(os.make_directory(path) == nil)
		delete(path)
	}
	for name in ([]string{"coast", "oranges"}) {
		source := fmt.aprintf("examples/demo3/assets/%s.png", name)
		path := fmt.aprintf("%s/%s.png", design_root, name)
		data, read_error := os.read_entire_file(source, context.allocator)
		assert(read_error == nil)
		assert(os.write_entire_file(path, data) == nil)
		delete(data); delete(source); delete(path)
	}
	for name in ([]string{"Notes.txt", "Archive.zip"}) {
		path := fmt.aprintf("%s/%s", design_root, name)
		assert(os.write_entire_file(path, "Sample file.\n") == nil)
		delete(path)
	}
	browser.initialized = true
	assert(read_and_wait(&browser, design_root))
	design_step = 0
	frames := [?]ui.Capture_Frame{
		{size = {640, 480}, scale = 2},
		{size = {640, 480}, scale = 2, path = "bin/file-manager-design.png"},
		{size = {640, 480}, scale = 2},
		{size = {640, 480}, scale = 2, input = {mouse_inside = true, mouse_position = {300, 250}, scroll_delta = {0, 800}}},
		{size = {640, 480}, scale = 2, path = "bin/file-manager-watch.png"},
		{size = {640, 480}, scale = 2},
		{size = {400, 360}, scale = 2, path = "bin/file-manager-compact.png"},
		{size = {320, 240}, scale = 2, path = "bin/file-manager-small.png"},
	}
	result := ui.capture_frames(design_update, frames[:])
	assert(result.error == .None)
	fmt.println("Verified thumbnails and watched directory refresh: additions/removals, scroll preservation and clamping")
}

@(private)
design_update :: proc() {
	defer { design_step += 1 }
	old_scroll := last_scroll
	if design_step == 2 || design_step == 4 || design_step == 5 {
		before := files.revision(browser.service, browser.active)
		for i in 0..<30 {
			path := fmt.aprintf("%s/Sample-%02d.txt", design_root, i)
			if design_step == 2 { assert(os.write_entire_file(path, "sample") == nil) }
			if design_step == 5 { assert(os.remove(path) == nil) }
			delete(path)
		}
		path := fmt.aprintf("%s/New.txt", design_root)
		if design_step == 4 { assert(os.write_entire_file(path, "new") == nil) }
		if design_step == 5 { assert(os.remove(path) == nil) }
		delete(path)
		// All waiting and filesystem writes here are capture-only.
		start := time.tick_now()
		for files.revision(browser.service, browser.active) <= before {
			assert(time.tick_since(start) < 10 * time.Second)
			time.sleep(time.Millisecond)
		}
	}
	update()
	if design_step == 1 {
		for row in list.rows {
			if browser.entries[row.index].info.name == "Notes.txt" { design_focus = row.id; ui.request_focus(row.id) }
		}
		assert(design_focus != (ui.Identity{}))
	}
	if design_step >= 2 {
		assert(ui.direct_focus() == design_focus)
		index := ui.virtual_list_focused_index(&list.view)
		assert(index >= 0 && browser.entries[index].info.name == "Notes.txt")
	}
	if design_step <= 1 {
		for name in ([]string{"coast", "oranges"}) {
			path := fmt.aprintf("%s/%s.png", design_root, name)
			defer delete(path)
			start := time.tick_now()
			for {
				result := ui.image_file(path, max_extent = 128)
				assert(result.error == "")
				if result.state == .Done {
					if design_step == 1 { assert(result.image != (ui.Image{})) }
					break
				}
				assert(time.tick_since(start) < 10 * time.Second)
				time.sleep(time.Millisecond)
			}
		}
	}
	if design_step == 2 { assert(len(browser.entries) == 36) }
	if design_step == 4 { assert(len(browser.entries) == 37 && last_scroll == old_scroll && last_scroll > 0) }
	if design_step == 5 { assert(len(browser.entries) == 6 && last_scroll == 0) }
}
