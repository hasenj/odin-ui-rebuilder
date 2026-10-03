package file_manager

import ui "../../core"
import "core:fmt"
import "core:strings"
import "core:math"

virtual_step: int
virtual_focus: ui.Identity

// Stress the production list with 20,000 folders. Bound declarations rather
// than asserting machine-specific timings, and exercise focus outside the
// visible range as well as large scroll jumps and clicks on newly shown rows.
capture_virtual_list :: proc() {
	destroy_browser(&browser)
	destroy_list()
	font = 0
	previous, pressed_id = {}, {}
	browser = Browser{initialized = true, generation = 1, path = strings.clone("/synthetic"), folders = 20000}
	for i in 0..<browser.folders {
		name := fmt.aprintf("Folder %06d", i)
		append(&browser.entries, Entry{info = {name = name, fullpath = name}, directory = true})
	}
	frames: [33]ui.Capture_Frame
	for &frame, i in frames { frame = {size = {780, 640}, scale = 1, time = f64(i) / 60} }
	for i in 1..=20 { frames[i].input.keys_pressed = {.Tab} }
	frames[21].input = {mouse_inside = true, mouse_position = {300, 250}, scroll_delta = {0, 400000}}
	frames[22].path = "bin/file-manager-virtual-middle.png"
	frames[23].input.keys_pressed = {.Tab}
	frames[24].input = {keys_pressed = {.Tab}, modifiers = {.Shift}}
	frames[25].input = {mouse_inside = true, mouse_position = {300, 250}, scroll_delta = {0, -1000000}}
	frames[26].input = {mouse_inside = true, mouse_position = {50, 43}, mouse_buttons = {.Left}}
	frames[27].input = {mouse_inside = true, mouse_position = {5, 5}}
	frames[28].input = {keys_pressed = {.Tab}, modifiers = {.Shift}}
	frames[28].path = "bin/file-manager-virtual-last.png"
	frames[29].input.keys_pressed = {.Tab}
	frames[30].input = {mouse_inside = true, mouse_position = {150, 544}, mouse_buttons = {.Left}}
	frames[31].input = {mouse_inside = true, mouse_position = {150, 544}}
	frames[32].size = {140, 100}
	result := ui.capture_frames(virtual_update, frames[:])
	assert(result.error == .None)
	assert(browser.reads == 0, "Virtual scrolling must not read directories")
	fmt.println("Verified 20,000-row virtualization: bounded declarations, offscreen focus, Tab traversal, scroll jumps and last-row click")
}

virtual_update :: proc() {
	if virtual_step == 32 {
		assert(browser.pending == "/synthetic/Folder 019999")
		delete(browser.pending)
		browser.pending = ""
	}
	update()
	assert(len(list.rows) == len(list.indices))
	assert(len(list.rows) <= list.end - list.first + 5)
	assert(len(list.rows) <= int(math.ceil(ui.current_frame().size.y / row_height)) + 6)
	focused := -1
	for row in list.rows {
		if row.id == ui.direct_focus() { focused = row.index }
	}
	if virtual_step >= 2 && virtual_step <= 20 { assert(focused == virtual_step - 2) }
	switch virtual_step {
	case 20:
		assert(last_scroll > 0)
		virtual_focus = ui.direct_focus()
	case 22:
		assert(list.first > 9000 && focused == 18 && ui.direct_focus() == virtual_focus)
	case 23: assert(focused == 19 && list.first < 20)
	case 24: assert(focused == 18)
	case 25: assert(last_scroll == 0 && focused == 18)
	case 28: assert(focused == 19999 && list.end == 20000)
	case 29: assert(focused == -1)
	case 32: assert(list.first == list.end)
	}
	virtual_step += 1
}
