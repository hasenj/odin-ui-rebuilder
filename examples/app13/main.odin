package app13

import ui "../../core"
import "core:fmt"
import "core:os"

ink :: ui.Color{0.92, 0.95, 1, 1}
muted :: ui.Color{0.58, 0.67, 0.78, 1}
pressed_id: ui.Identity
previous, pressed, released: ui.Mouse_Buttons
clicks, builds: int
selected: int = -1
reverse_order: bool

main :: proc() {
	if len(os.args) == 2 && os.args[1] == "--capture" {
		frames := [?]ui.Capture_Frame{
			{path = "bin/app13-wide.png", size = {920, 700}, scale = 2},
			// Click the stretched part of the short first menu entry.
			{size = {920, 700}, scale = 2, time = 0.01, input = {mouse_inside = true, mouse_position = {175, 215}, mouse_buttons = {.Left}}},
			{path = "bin/app13-menu.png", size = {920, 700}, scale = 2, time = 0.15, input = {mouse_inside = true, mouse_position = {175, 215}}},
			{size = {920, 700}, scale = 2, time = 0.2, input = {mouse_inside = true, mouse_position = {70, 135}, mouse_buttons = {.Left}}},
			{path = "bin/app13-reordered.png", size = {920, 700}, scale = 2, time = 0.3, input = {mouse_inside = true, mouse_position = {70, 135}}},
			{path = "bin/app13-narrow.png", size = {500, 780}, scale = 2, time = 0.4},
			{path = "bin/app13-small.png", size = {270, 600}, scale = 1, time = 0.5},
		}
		result := ui.capture_frames(update, frames[:])
		assert(result.error == .None)
		assert(builds == len(frames), "Layout must not replay component code")
		assert(clicks == 2 && selected == 0 && reverse_order, "Stretched menu hit and reorder must each activate once")
		fmt.println("Verified content layout: stretched menu interaction, separate cut groups, wrapping and reorder")
		return
	}
	ui.open_window("Odin UI Rebuilder — Content layout and menus", 920, 700, update, frame_timing = .Summary)
}

update :: proc() {
	builds += 1
	if _, found := ui.find_font("UI"); !found {
		_, err := ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf", "UI")
		assert(err == .None)
	}
	input := ui.current_frame().input
	pressed = input.mouse_pressed | (input.mouse_buttons & ~previous)
	released = input.mouse_released | (previous & ~input.mouse_buttons)
	previous = input.mouse_buttons
	ui.paint(color = {0.045, 0.06, 0.085, 1})
	ui.pad(24)
	ui.open_clip()
	ui.open_layout(.Top, {gap = 12})
	ui.text_item("LOCAL LAYOUT / 13", "UI", 13, muted)
	ui.text_item("Sized by content.", "UI", 30, ink, weight = 650)
	finish_layout()
	ui.pad4(18, 0, 0, 0)

	// Cutting places two independent content-sized groups at opposite edges.
	ui.open_rect(.Top, 52)
	ui.open_clip()
	ui.open_layout(.Left, {flow = .Row, gap = 8})
	if button("Reverse menu", -1) { reverse_order = !reverse_order }
	finish_layout()
	ui.open_layout(.Right, {flow = .Row})
	if button("Reset", -2) { selected = -1 }
	finish_layout()
	ui.close_clip()
	ui.close_rect()
	ui.pad4(20, 0, 0, 0)

	ui.open_rect(.Bottom, 52)
	footer := ui.current_rect()
	ui.close_rect()

	// The widest label sets the menu width. Stretch makes all row backgrounds
	// and hit regions use that width, without growing the menu into spare space.
	ui.open_layout(.Left, {gap = 6, padding = {12, 12}, stretch = true})
	ui.paint(color = {0.075, 0.10, 0.15, 1}, corners = 14)
	labels := [4]string{"New file", "Open workspace", "Save all changes", "Preferences"}
	order := [4]int{0, 1, 2, 3}
	if reverse_order { order = {3, 2, 1, 0} }
	for i in order {
		if button(labels[i], i, chosen = selected == i) { selected = i }
	}
	finish_layout()

	ui.pad4(0, 0, 0, 24)
	ui.open_clip()
	ui.open_layout(.Top, {gap = 14, padding = {20, 20}})
	ui.paint(color = {0.075, 0.10, 0.15, 1}, corners = 14)
	ui.text_item("A menu that knows its size", "UI", 23, ink, weight = 650)
	ui.text_item("The longest entry determines the menu width. Shorter entries stretch across it, so their backgrounds and clickable areas line up. The menu keeps its content height and leaves the space below empty.", "UI", 17, muted)
	ui.text_item("Rect cutting places the menu on the left and this explanation in the remainder. It also separates the toolbar groups. Neither layout distributes spare space or shrinks its siblings.", "UI", 17, muted)
	ui.open_box({flow = .Row, gap = 8, stretch = true})
	for i in 0..<3 {
		ui.open_box({padding = {8, 10}}, key = i)
		ui.paint(color = {0.13, 0.17, 0.24, 1}, corners = 6)
		buffer: [32]u8
		label := fmt.bprintf(buffer[:], "Item %d", i + 1)
		ui.text_item(label, "UI", 14, ink)
		for &byte in buffer { byte = 'X' }
		ui.close_box()
	}
	ui.close_box()
	finish_layout()
	ui.close_clip()
	ui.open_rect_at(footer)
	ui.open_layout(.Top)
	buffer: [96]u8
	ui.text_item(fmt.bprintf(buffer[:], "%d clicks / hover a whole menu row / Tab to change focus", clicks), "UI", 14, muted)
	finish_layout()
	ui.close_rect()
	ui.close_clip()
	if .Left in released { pressed_id = {} }
}

button :: proc(label: string, key: int, chosen: bool = false) -> bool {
	ui.open_box({padding = {10, 14}}, key = key)
	id := ui.current_identity()
	ui.focusable()
	if ui.hovered() && .Left in pressed { pressed_id = id }
	clicked := .Left in released && pressed_id == id && ui.hovered()
	if clicked { clicks += 1 }
	amount := ui.animate_f32(1 if ui.hovered() || ui.focused() || chosen else 0)
	normal := ui.Color{0.11, 0.19, 0.29, 1}
	ui.paint(color = normal + (ui.Color{0.17, 0.40, 0.68, 1} - normal) * amount, corners = 7)
	ui.text_item(label, "UI", 16, ink, weight = 600)
	ui.close_box()
	return clicked
}

finish_layout :: proc() {
	_, err := ui.close_layout()
	assert(err == .None)
}
