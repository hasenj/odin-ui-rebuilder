package file_manager

import ui "../../core"
import edit "../../core/edit"
import "core:fmt"
import "core:strings"

ahead_step: int
ahead_searches: u64

// Real UI builder plus native-shaped text snapshots. The target identity is
// taken from the previous frame exactly as in the macOS text-input adapter.
capture_typeahead :: proc() {
	destroy_browser(&browser); destroy_list()
	font = 0; previous, pressed_id = {}, {}
	browser = Browser{initialized = true, generation = 1, path = strings.clone("/synthetic"), folders = 2000}
	for i in 0..<20000 {
		name := fmt.aprintf("A folder %06d", i) if i < 1998 else strings.clone("Documents") if i == 1998 else strings.clone("Downloads") if i == 1999 else strings.clone("日本語.txt") if i == 15000 else strings.clone("École.txt") if i == 15001 else fmt.aprintf("File %06d.txt", i)
		append(&browser.entries, Entry{info = {name = name, fullpath = name}, directory = i < browser.folders})
	}
	frames: [29]ui.Capture_Frame
	for &frame, i in frames { frame = {size = {780, 640}, scale = 1, time = f64(i) / 10 + (2 if i >= 5 else 0)} }
	frames[3].path = "bin/file-manager-typeahead-directory.png"
	frames[5].path = "bin/file-manager-typeahead-file.png"
	frames[4].input = {keys_pressed = {.Space}, text = {handled_keys = {.Space}}}
	frames[7].input = {keys_pressed = {.Enter}, text = {handled_keys = {.Enter}}}
	frames[20].input = {mouse_inside = true, mouse_position = {200, 240}, scroll_delta = {0, -2000000}}
	frames[22].input.keys_pressed = {.Tab}
	frames[25].input = {keys_pressed = {.Tab}, text = {handled_keys = {.Tab}}}
	result := ui.capture_frames(typeahead_update, frames[:]); assert(result.error == .None)
	fmt.println("Verified type-to-select: 20,000 entries, prefix/timeout/cycling, files, IME, no match, reveal, Enter and idle work")
}

typeahead_update :: proc() {
	if ahead_step == 16 {
		assert(browser.pending == "/synthetic/Downloads")
		delete(browser.pending); browser.pending = ""
		browser.generation += 1
	}
	operation: ui.Text_Operation
	has_operation := true
	switch ahead_step {
	case 1: operation = {kind = .Commit, text = "d"}
	case 2: operation = {kind = .Commit, text = "o"}
	case 3: operation = {kind = .Commit, text = "w"}
	case 4: operation = {kind = .Commit, text = " "}
	case 5: operation = {kind = .Commit, text = "FILE 019999"}
	case 6: operation = {kind = .Mark, text = "にほん", selection = {9, 9}, replacement = {0, len(edit.value(&list.search.buffer))}, has_replacement = true}
	case 7: operation = {kind = .Commit, text = "Doc"}
	case 8: operation = {kind = .Command, command = .Backspace}
	case 9, 11: operation = {kind = .Command, command = .Cancel}
	case 10: operation = {kind = .Commit, text = "no-such-name"}
	case 12, 13: operation = {kind = .Commit, text = "d"}
	case 14: operation = {kind = .Commit, text = "ow"}
	case 15: operation = {kind = .Command, command = .Submit}
	case 24: operation = {kind = .Mark, text = "にほん", selection = {9, 9}}
	case 26: operation = {kind = .Commit, text = "日本"}
	case 27: operation = {kind = .Command, command = .Cancel}
	case 28: operation = {kind = .Commit, text = "é"}
	case 18: operation = {kind = .Commit, text = "File 010000"}
	case: has_operation = false
	}
	if has_operation {
		ui.current_frame().input.text.target = list.search.target
		ui.current_frame().input.text.operations = []ui.Text_Operation{operation}
	}
	update()
	assert(len(list.rows) <= list.end - list.first + 5, "Search must preserve bounded list declarations")
	selected := focused_row()
	switch ahead_step {
	case 1, 2, 7, 8, 9, 10, 11, 13: assert(selected == 1998)
	case 3, 4, 12, 14, 15: assert(selected == 1999)
	case 5, 6: assert(selected == 19999)
	case 17: assert(edit.value(&list.search.buffer) == "")
	case 18: assert(selected == 10000); ahead_searches = list.search.searches
	case 20, 21: assert(selected == 10000 && last_scroll == 0 && list.search.searches == ahead_searches)
	case 22, 23: assert(selected == 10001 && last_scroll > 0 && list.search.searches == ahead_searches)
	case 24, 25: assert(selected == 10001 && list.search.buffer.composing && list.search.searches == ahead_searches)
	case 26, 27: assert(selected == 15000)
	case 28: assert(selected == 15001)
	case:
	}
	if ahead_step == 3 || ahead_step == 5 { assert(selected >= list.first && selected < list.end && last_scroll > 0) }
	if ahead_step == 4 { assert(browser.pending == "", "Typing Space must not activate a directory") }
	if ahead_step == 6 { assert(list.search.buffer.composing && list.search.target == ui.text_target(ui.direct_focus())) }
	if ahead_step == 7 { assert(browser.pending == "", "IME commit must not also open the matched folder") }
	if ahead_step == 10 { assert(list.search.no_match) }
	ahead_step += 1
}
