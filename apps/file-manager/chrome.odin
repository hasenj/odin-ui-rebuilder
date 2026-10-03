package file_manager

import ui "../../core"
import "core:path/filepath"
import "core:strings"
import "core:fmt"

// Custom decorations occupy the address row itself. Like native window chrome,
// Close is pointer-only; it does not add a stop to file-list Tab traversal.
address_bar :: proc() {
	ui.open_rect(.Top, address_height)
	ui.paint(color = chrome)
	ui.pad2(4, 6)
	ui.open_rect(.Right, 28)
	id := ui.current_identity()
	if ui.hovered() && .Left in pressed { pressed_id = id }
	if ui.hovered() && .Left in released && pressed_id == id {
		ui.request_close(ui.current_window())
	}
	amount := ui.animate_f32(1 if ui.hovered() else 0)
	ui.paint(color = {0.65, 0.25, 0.24, amount}, corners = 3)
	label("×", 22, ink, align = .Center)
	ui.close_rect()
	ui.open_rect(.Left, 30)
	parent := filepath.dir(browser.path)
	if up_button(browser.path != "" && parent != browser.path) { queue_directory(&browser, parent) }
	ui.close_rect()
	// Only the unused address area moves the native window, never its controls
	// or file rows. Tiled Wayland windows use the compositor's move bindings.
	ui.window_drag_region(ui.current_rect())
	ui.pad2(0, 10)
	path := browser.path if browser.path != "" else "Files"
	if home_path != "" && (path == home_path || (strings.has_prefix(path, home_path) && len(path) > len(home_path) && path[len(home_path)] == '/')) {
		path = fmt.tprintf("~%s", path[len(home_path):])
	}
	metrics, err := ui.measure_text(path, font, 13)
	overflow := err == .None && metrics.width > ui.current_rect().size.x
	if overflow {
		ui.open_rect(.Left, 14)
		label("…", 13, muted)
		ui.close_rect()
	}
	label(path, 13, ink, align = .End if overflow else .Start)
	ui.close_rect()
}

// A thin position indicator; wheel/trackpad and keyboard provide scrolling.
paint_scrollbar :: proc(scroll: ui.Scroll_State) {
	if scroll.max_offset.y <= 0 || scroll.viewport.size.y <= 0 { return }
	track := scroll.viewport
	height := min(track.size.y, max(18, track.size.y * track.size.y / scroll.content_size.y))
	y := (track.size.y - height) * scroll.offset.y / scroll.max_offset.y
	ui.open_rect_at({track.position + [2]f32{max(0, track.size.x - 6), y}, {4, height}})
	ui.set_hit_test(false)
	ui.paint(color = {0.42, 0.46, 0.49, 0.7}, corners = 2)
	ui.close_rect()
}
