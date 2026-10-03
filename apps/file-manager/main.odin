package file_manager

import ui "../../core"
import edit "../../core/edit"
import "core:os"
import "core:fmt"
import "core:path/filepath"
import "core:strings"

ink :: ui.Color{0.10, 0.16, 0.23, 1}
muted :: ui.Color{0.40, 0.46, 0.51, 1}
blue :: ui.Color{0.12, 0.46, 0.48, 1}
row_height :: f32(56)

browser: Browser
font: ui.Font
previous, pressed, released: ui.Mouse_Buttons
pressed_id: ui.Identity
last_scroll: f32 // Also observed by the synthetic navigation check.

main :: proc() {
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
	ui.open_window("Files", 780, 640, update, frame_timing = .Summary, transparent = false)
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
	ui.paint(color = {0.965, 0.962, 0.95, 1})
	ui.pad(24)
	ui.open_clip()

	ui.open_rect(.Top, 72)
	ui.open_rect(.Left, 58)
	ui.open_rect(.Top, 44)
	parent := filepath.dir(browser.path)
	can_go_up := browser.path != "" && parent != browser.path
	if button("Up", can_go_up) { queue_directory(&browser, parent) }
	ui.close_rect()
	ui.close_rect()
	ui.pad4(0, 0, 0, 20)
	ui.open_rect(.Top, 38)
	title := filepath.base(browser.path) if browser.path != "" else "Files"
	label(title, 28, ink, weight = 650)
	ui.close_rect()
	label(browser.path, 14, muted)
	ui.close_rect()

	ui.open_rect(.Bottom, 32)
	ui.pad4(8, 0, 0, 0)
	if query := edit.value(&list.search.buffer); query != "" {
		prefix := "No match: " if list.search.no_match else "Find: "
		label(fmt.tprintf("%s%s", prefix, query), 13, ink)
	} else if browser.error != "" {
		label(browser.error, 13, {0.65, 0.25, 0.20, 1})
	} else {
		if ui.current_rect().size.x >= 430 {
			ui.open_rect(.Right, 190)
			status := "Reading..." if browser.state == .Reading else "Watching for changes" if browser.active != nil else "Ready"
			label(status, 13, blue, align = .End)
			ui.close_rect()
		}
		buffer: [96]u8
		label(fmt.bprintf(buffer[:], "%d folders / %d files", browser.folders, len(browser.entries) - browser.folders), 13, muted)
	}
	ui.close_rect()
	ui.pad4(16, 0, 8, 0)
	ui.paint(color = {1, 1, 1, 1}, corners = 12)
	ui.pad(8)
	ui.open_rect(.Top, 32)
	ui.paint(color = {0.962, 0.967, 0.97, 1}, corners = 5)
	ui.pad2(0, 12)
	columns("KIND", "SIZE", true)
	ui.pad4(0, 0, 0, 52)
	label("NAME", 11, muted, weight = 600)
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
		ui.pad(16)
		label("Reading folder..." if browser.state == .Reading else "This folder is empty." if browser.error == "" else "Folder unavailable.", 17, muted)
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
			ui.paint(color = {0.72, 0.88, 0.87, amount * 0.65}, corners = 5)
			ui.open_rect(.Bottom, 1)
			ui.paint(color = {0.94, 0.95, 0.955, 1})
			ui.close_rect()
			ui.pad2(0, 12)
			buffer: [48]u8
			size := "—" if entry.directory else file_size(entry.info.size, buffer[:])
			columns(file_kind(entry), size, false)
			ui.open_rect(.Left, 52)
			file_icon(entry)
			ui.close_rect()
			label(entry.info.name, 16, ink)

		}
		ui.close_rect()
	}
	ui.close_scroll()
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

button :: proc(value: string, enabled: bool) -> bool {
	ui.focusable(enabled)
	publish_typeahead()
	clicked := activated(enabled)
	amount := ui.animate_f32(1 if enabled && (ui.hovered() || ui.focused()) else 0)
	base := ui.Color{0.91, 0.93, 0.93, 1}
	ui.paint(color = base + (ui.Color{0.72, 0.87, 0.86, 1} - base) * amount, corners = 7)
	label(value, 16, ink if enabled else muted, align = .Center)
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
