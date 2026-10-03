package app14

import ui "../../core"
import "core:os"
import "core:fmt"
import "core:path/filepath"
import "core:strings"

ink :: ui.Color{0.91, 0.94, 0.98, 1}
muted :: ui.Color{0.52, 0.60, 0.69, 1}
blue :: ui.Color{0.49, 0.72, 1, 1}
row_height :: f32(40)

browser: Browser
font: ui.Font
previous, pressed, released: ui.Mouse_Buttons
pressed_id: ui.Identity
last_scroll: f32 // Also observed by the synthetic navigation check.

main :: proc() {
	defer destroy_browser(&browser)
	if len(os.args) == 2 && os.args[1] == "--capture" { capture_check(); return }
	if len(os.args) > 2 {
		fmt.eprintln("Usage: app14 [directory | --capture]")
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
		if err == nil { browse(&browser, home); delete(home) } else { set_error(&browser, err) }
	}
	if browser.pending != "" {
		pending := browser.pending
		browser.pending = ""
		if browse(&browser, pending) { ui.clear_focus(); pressed_id = {} }
		delete(pending)
	}
	if font == 0 {
		err: ui.Text_Error
		font, err = ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf")
		assert(err == .None)
	}
	input := ui.current_frame().input
	pressed = input.mouse_pressed | (input.mouse_buttons & ~previous)
	released = input.mouse_released | (previous & ~input.mouse_buttons)
	previous = input.mouse_buttons
	ui.paint(color = {0.045, 0.058, 0.075, 1})
	ui.pad(24)
	ui.open_clip()

	ui.open_rect(.Top, 64)
	ui.open_rect(.Left, 76)
	ui.open_rect(.Top, 38)
	parent := filepath.dir(browser.path)
	can_go_up := browser.path != "" && parent != browser.path
	if button("Up", can_go_up) { queue_directory(&browser, parent) }
	ui.close_rect()
	ui.close_rect()
	ui.pad4(0, 0, 0, 18)
	ui.open_rect(.Top, 32)
	label("Files", 27, ink, weight = 650)
	ui.close_rect()
	label(browser.path, 14, muted)
	ui.close_rect()

	ui.open_rect(.Bottom, 36)
	ui.pad4(10, 0, 0, 0)
	if browser.error != "" {
		label(browser.error, 14, {1, 0.59, 0.47, 1})
	} else {
		buffer: [96]u8
		label(fmt.bprintf(buffer[:], "%d folders / %d files", browser.folders, len(browser.entries) - browser.folders), 14, muted)
	}
	ui.close_rect()
	ui.pad4(12, 0, 8, 0)
	ui.paint(color = {0.063, 0.080, 0.105, 1}, corners = 10)
	ui.pad(8)
	// A new directory gets a fresh subtree, so old hover, focus and scrolling
	// cannot transfer to an unrelated row with the same array index.
	ui.open_identity(key = browser.generation)
	ui.open_scroll({ui.current_rect().size.x, f32(len(browser.entries)) * row_height})
	viewport := ui.current_bounds()
	last_scroll = ui.current_scroll().offset.y
	if len(browser.entries) == 0 {
		ui.pad(16)
		label("This folder is empty." if browser.error == "" else "Folder unavailable.", 17, muted)
	}
	for entry, i in browser.entries {
		ui.open_rect(.Top, row_height, key = i)
		ui.focusable(entry.directory)
		if activated(entry.directory) {
			// Preserve the browsed path, including symlink aliases, so Up returns
			// to the directory the user actually came from.
			path, _ := filepath.join({browser.path, entry.info.name})
			queue_directory(&browser, path)
			delete(path)
		}
		r := ui.current_rect()
		// Keep all rows available to focus traversal, but prepare/draw text only
		// for visible rows. Long directories do not rasterize offscreen names.
		if r.position.y < viewport.position.y + viewport.size.y && r.position.y + r.size.y > viewport.position.y {
			active := entry.directory && (ui.hovered() || ui.focused())
			amount := ui.animate_f32(1 if active else 0)
			ui.paint(color = {0.12, 0.24, 0.38, amount}, corners = 6)
			ui.pad2(0, 12)
			if entry.directory {
				ui.open_rect(.Right, 22)
				label("/", 18, blue)
				ui.close_rect()
			}
			label(entry.info.name, 17, blue if entry.directory else ink)
		}
		ui.close_rect()
	}
	ui.close_scroll()
	ui.close_identity()
	ui.close_clip()
	if .Left in released { pressed_id = {} }
}

activated :: proc(enabled: bool) -> bool {
	if !enabled { return false }
	id := ui.current_identity()
	if ui.hovered() && .Left in pressed { pressed_id = id }
	input := ui.current_frame().input
	return (.Left in released && pressed_id == id && ui.hovered()) ||
		(ui.focused() && (.Enter in input.keys_pressed || .KeypadEnter in input.keys_pressed || .Space in input.keys_pressed))
}

button :: proc(value: string, enabled: bool) -> bool {
	ui.focusable(enabled)
	clicked := activated(enabled)
	amount := ui.animate_f32(1 if enabled && (ui.hovered() || ui.focused()) else 0)
	base := ui.Color{0.11, 0.15, 0.20, 1}
	ui.paint(color = base + (ui.Color{0.16, 0.31, 0.48, 1} - base) * amount, corners = 7)
	label(value, 16, ink if enabled else muted, align = .Center)
	return clicked
}

// Fixed-size, single-line names, clipped rather than made unreadably small.
// Until font fallback exists, display unsupported names as reversible byte
// escapes. The original filesystem name is always used for navigation.
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
