package file_manager

import ui "../../core"
import edit "../../core/edit"
import "core:os"
import "core:fmt"
import "core:path/filepath"
import "core:strings"

ink :: ui.Color{0.90, 0.92, 0.93, 1}
muted :: ui.Color{0.60, 0.66, 0.69, 1}
blue :: ui.Color{0.22, 0.72, 0.69, 1}
row_height :: f32(30)
address_height :: f32(36)
column_height :: f32(24)
footer_height :: f32(24)
list_top :: address_height + column_height
chrome :: ui.Color{0.14, 0.16, 0.18, 1}

browser: Browser
font: ui.Font
home_path: string
previous, pressed, released: ui.Mouse_Buttons
pressed_id: ui.Identity
last_scroll: f32 // Also observed by the synthetic navigation check.

main :: proc() {
	home_path, _ = os.user_home_dir(context.allocator)
	defer delete(home_path)
	defer destroy_browser(&browser)
	defer destroy_list()
	if len(os.args) == 2 && os.args[1] == "--bench" { benchmark_list(); return }
	if len(os.args) == 2 && os.args[1] == "--capture" { capture_check(); capture_design(); capture_virtual_list(); capture_typeahead(); return }
	if len(os.args) > 2 {
		fmt.eprintln("Usage: file-manager [directory | --capture | --bench]")
		os.exit(1)
	}
	if len(os.args) == 2 {
		browser.initialized = true
		browse(&browser, os.args[1])
	}
	ui.open_window("Files", 640, 480, update, frame_timing = .Summary, decorated = false, transparent = false)
}

update :: proc() {
	if !browser.initialized {
		browser.initialized = true
		home, err := os.user_home_dir(context.allocator)
		if err == nil { browse(&browser, home); delete(home) } else { browser.error = fmt.aprintf("Could not locate home: %v", err) }
	}
	if browser.pending != "" {
		pending := browser.pending
		browser.pending = ""
		browse(&browser, pending)
		delete(pending)
	}
	changed := poll_browser(&browser)
	if changed { ui.clear_focus(); pressed_id = {} }
	if font == 0 {
		err: ui.Text_Error
		font, err = ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf")
		assert(err == .None)
	}
	input := ui.current_frame().input
	pressed = input.mouse_pressed | (input.mouse_buttons & ~previous)
	released = input.mouse_released | (previous & ~input.mouse_buttons)
	previous = input.mouse_buttons
	if input.mouse_cancelled { pressed_id = {}; pressed, released = {}, {} }
	// The root owns text input while no control has focus. Once a control
	// takes focus, omit the root from Tab traversal so the existing order stays.
	if ui.direct_focus() == (ui.Identity{}) { ui.request_focus() }
	ui.focusable(ui.direct_focus() == ui.current_identity())
	update_typeahead()
	ui.paint(color = {0.105, 0.12, 0.135, 1})
	ui.open_clip()
	address_bar()
	ui.open_rect(.Bottom, footer_height)
	ui.paint(color = chrome)
	ui.pad2(0, 10)
	if query := edit.value(&list.search.buffer); query != "" {
		prefix := "No match: " if list.search.no_match else "Find: "
		label(fmt.tprintf("%s%s", prefix, query), 12, ink)
	} else if browser.error != "" {
		label(browser.error, 12, {1, 0.55, 0.48, 1})
	} else {
		buffer: [96]u8
		label("Reading folder…" if browser.state == .Reading else fmt.bprintf(buffer[:], "%d folders · %d files", browser.folders, len(browser.entries) - browser.folders), 11, muted)
	}
	ui.close_rect()
	ui.open_rect(.Top, column_height)
	ui.paint(color = chrome)
	ui.pad2(0, 12)
	columns("Kind", "Size", true)
	label("Name", 12, muted)
	ui.close_rect()
	// A new directory gets a fresh subtree, so old hover, focus and scrolling
	// cannot transfer to an unrelated row with the same array index.
	ui.open_identity(key = browser.generation)
	ui.open_scroll({ui.current_rect().size.x, f32(len(browser.entries)) * row_height})
	if changed && browser.refresh { ui.scroll_to({0, last_scroll}) }
	viewport := ui.current_bounds()
	if list.search.match >= 0 {
		offset := ui.current_scroll().offset.y
		top := f32(list.search.match) * row_height
		if top < offset { offset = top }
		if top + row_height > offset + viewport.size.y { offset = top + row_height - viewport.size.y }
		ui.scroll_to({0, offset})
	}
	last_scroll = ui.current_scroll().offset.y
	canvas := ui.current_rect()
	prepare_list(len(browser.entries), browser.generation, last_scroll, viewport.size.y)
	if len(browser.entries) == 0 {
		ui.pad(12)
		label("Reading folder..." if browser.state == .Reading else "This folder is empty." if browser.error == "" else "Folder unavailable.", 13, muted)
	}
	for i in list.indices {
		entry := browser.entries[i]
		ui.open_rect_at({position = canvas.position + [2]f32{0, f32(i) * row_height},
			size = {canvas.size.x, row_height}}, key = i)
		append(&list.rows, Row_Identity{i, ui.current_identity()})
		ui.focusable()
		if i == list.search.match { ui.request_focus() }
		publish_typeahead()
		if activated(entry.directory) {
			// Preserve the browsed path, including symlink aliases, so Up returns
			// to the directory the user actually came from.
			path, _ := filepath.join({browser.path, entry.info.name})
			queue_directory(&browser, path)
			delete(path)
		}
		// Offscreen keyboard targets retain geometry without painting.
		if i >= list.first && i < list.end {
			selected := i == list.search.match if list.search.match >= 0 else ui.focused()
			active := selected || (entry.directory && ui.hovered())
			amount := ui.animate_f32(1 if active else 0)
			ui.paint(color = {0.08, 0.38, 0.39, amount * 0.65})
			ui.pad2(0, 12)
			buffer: [48]u8
			size := "—" if entry.directory else file_size(entry.info.size, buffer[:])
			columns(file_kind(entry), size, false)
			ui.open_rect(.Left, 28)
			file_icon(entry)
			ui.close_rect()
			label(entry.info.name, 13, ink)

		}
		ui.close_rect()
	}
	view_scroll := ui.current_scroll()
	ui.close_scroll()
	paint_scrollbar(view_scroll)
	ui.close_identity()
	ui.close_clip()
	ui.focusable(ui.direct_focus() == ui.current_identity())
	publish_typeahead()
	if .Left in released { pressed_id = {} }
}

activated :: proc(enabled: bool) -> bool {
	if !enabled { return false }
	id := ui.current_identity()
	if ui.hovered() && .Left in pressed { pressed_id = id }
	input := ui.current_frame().input
	return (.Left in released && pressed_id == id && ui.hovered()) ||
		(ui.focused() && (list.search.match < 0 || focused_row() == list.search.match) && (list.search.submit ||
		(.Enter in input.keys_pressed && .Enter not_in input.text.handled_keys) ||
		(.KeypadEnter in input.keys_pressed && .KeypadEnter not_in input.text.handled_keys) ||
		(.Space in input.keys_pressed && .Space not_in input.text.handled_keys)))
}

up_button :: proc(enabled: bool) -> bool {
	ui.focusable(enabled)
	publish_typeahead()
	clicked := activated(enabled)
	amount := ui.animate_f32(1 if enabled && (ui.hovered() || ui.focused()) else 0)
	base := ui.Color{0.19, 0.22, 0.24, 1}
	ui.paint(color = base + (ui.Color{0.16, 0.36, 0.37, 1} - base) * amount, corners = 4)
	// Draw the navigation arrow from geometry, independent of font coverage.
	color := ink if enabled else muted
	r := ui.current_rect()
	origin := r.position + (r.size - [2]f32{12, 14}) / 2
	ui.open_rect_at({origin + [2]f32{5, 1}, {2, 13}})
	ui.paint(color = color)
	ui.close_rect()
	for i in 0..<6 {
		ui.open_rect_at({origin + [2]f32{f32(5-i), f32(i)}, {2, 2}}, key = i)
		ui.paint(color = color)
		ui.close_rect()
		ui.open_rect_at({origin + [2]f32{f32(5+i), f32(i)}, {2, 2}}, key = i + 6)
		ui.paint(color = color)
		ui.close_rect()
	}
	return clicked
}

// Fixed-size, single-line names, clipped rather than made unreadably small.
// Invalid/control-containing names use reversible byte escapes. Unsupported
// glyphs render as tofu; navigation always uses the original filesystem name.
label :: proc(value: string, size: f32, color: ui.Color, weight: f32 = 0, align: ui.Text_Align = .Start) {
	r := ui.current_rect()
	if r.size.x <= 0 || r.size.y <= 0 { return }
	layout, err := ui.layout_text_fit(value, font, r.size.x, size, min_scale = 1, weight = weight)
	if err != .None {
		builder := strings.builder_make(allocator = context.temp_allocator)
		for byte in transmute([]u8)value {
			if byte >= 32 && byte < 127 && byte != '\\' { strings.write_byte(&builder, byte) } else {
				fmt.sbprintf(&builder, "\\x%02X", byte)
			}
		}
		layout, err = ui.layout_text_fit(strings.to_string(builder), font, r.size.x, size, min_scale = 1, weight = weight)
	}
	if err != .None { return }
	ui.open_clip()
	_ = ui.draw_text_layout(layout, color, align = align, valign = .Center)
	ui.close_clip()
}
