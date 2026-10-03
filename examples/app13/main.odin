package app13

import ui "../../core"
import "core:fmt"
import "core:os"

ink :: ui.Color{0.92, 0.95, 1, 1}
muted :: ui.Color{0.58, 0.67, 0.78, 1}
ids: [3]ui.Identity
pressed_id: ui.Identity
previous: ui.Mouse_Buttons
clicks: int
reverse_order: bool
builds: int
card_height: f32

main :: proc() {
	if len(os.args) == 2 && os.args[1] == "--capture" {
		frames := [?]ui.Capture_Frame{
			{path = "bin/app13-wide.png", size = {920, 700}, scale = 2},
			{size = {920, 700}, scale = 2, time = 0.01, input = {mouse_inside = true, mouse_position = {70, 140}, mouse_buttons = {.Left}}},
			{path = "bin/app13-click.png", size = {920, 700}, scale = 2, time = 0.15, input = {mouse_inside = true, mouse_position = {70, 140}}},
			{path = "bin/app13-narrow.png", size = {440, 780}, scale = 2, time = 0.2},
			{path = "bin/app13-small.png", size = {270, 600}, scale = 1, time = 0.3},
		}
		result := ui.capture_frames(update, frames[:])
		assert(result.error == .None)
		assert(builds == len(frames), "Layout must not replay component code")
		assert(clicks == 1 && reverse_order, "Click must activate exactly once")
		fmt.println("Verified local layout: single execution, click/reorder, wrapping and captures")
		return
	}
	ui.open_window("Odin UI Rebuilder — Local layout", 920, 700, update, frame_timing = .Summary)
}

update :: proc() {
	builds += 1
	if _, found := ui.find_font("UI"); !found {
		_, err := ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf", "UI")
		assert(err == .None)
	}
	input := ui.current_frame().input
	pressed := input.mouse_pressed | (input.mouse_buttons & ~previous)
	released := input.mouse_released | (previous & ~input.mouse_buttons)
	previous = input.mouse_buttons
	ui.paint(color = {0.045, 0.06, 0.085, 1})
	ui.pad(24)
	ui.open_clip()
	ui.open_layout(.Top, {gap = 18})
	ui.text_item("LOCAL LAYOUT / 13", "UI", 13, muted)
	ui.text_item("Content sets the pace.", "UI", 30, ink, weight = 650)
	_, err := ui.close_layout()
	assert(err == .None)
	ui.pad4(18, 0, 0, 0)
	ui.open_layout(.Top, {flow = .Row, gap = 12})
	order := [3]int{0, 1, 2}
	if reverse_order { order = {2, 1, 0} }
	labels := [3]string{"Reverse order", "A longer action label", "Another action"}
	for i in order {
		ui.open_box({padding = {12, 16}}, key = i)
		ids[i] = ui.current_identity()
		ui.focusable()
		if ui.hovered() && .Left in pressed { pressed_id = ids[i] }
		if .Left in released && pressed_id == ids[i] && ui.hovered() {
			clicks += 1
			if i == 0 { reverse_order = !reverse_order }
		}
		amount := ui.animate_f32(1 if ui.hovered() || ui.focused() else 0)
		normal := ui.Color{0.11, 0.19, 0.29, 1}
		ui.paint(color = normal + (ui.Color{0.17, 0.40, 0.68, 1} - normal) * amount, corners = 10)
		ui.text_item(labels[i], "UI", 17, ink, weight = 600)
		ui.close_box()
	}
	_, err = ui.close_layout()
	assert(err == .None)
	if .Left in released { pressed_id = {} }
	ui.pad4(22, 0, 0, 0)
	ui.open_layout(.Top, {flow = .Row, gap = 16, padding = {20, 20}})
	ui.paint(color = {0.075, 0.10, 0.15, 1}, corners = 14)
	ui.open_box({width = ui.layout_fixed(52), height = ui.layout_fixed(52)})
	ui.paint(color = {0.89, 0.51, 0.25, 1}, corners = 12)
	ui.close_box()
	ui.open_box({width = ui.layout_fill(), gap = 12})
	ui.text_item("A small layout inside a cut rectangle", "UI", 21, ink, weight = 650)
	ui.text_item("This paragraph wraps to the width that remains beside the icon. Its height sizes the column, then the card, then the strip cut from the surrounding interface. Resize the window to see everything below follow it.", "UI", 17, muted)
	ui.open_box({flow = .Row, gap = 8, width = ui.layout_fill()})
	for i in 0..<3 {
		ui.open_box({width = ui.layout_fill(), padding = {8, 10}}, key = i)
		ui.paint(color = {0.13, 0.17, 0.24, 1}, corners = 6)
		buffer: [32]u8
		label := fmt.bprintf(buffer[:], "Item %d", i + 1)
		ui.text_item(label, "UI", 14, ink)
		// Prove deferred text does not borrow this reusable local buffer.
		for &byte in buffer { byte = 'X' }
		ui.close_box()
	}
	ui.close_box()
	ui.close_box()
	card, card_err := ui.close_layout()
	assert(card_err == .None)
	card_height = card.size.y
	ui.pad4(20, 0, 0, 0)
	ui.open_layout(.Top, {gap = 8})
	buffer: [96]u8
	ui.text_item(fmt.bprintf(buffer[:], "%d clicks / same identities after reordering", clicks), "UI", 15, ink)
	ui.text_item("Hover and click the buttons. Tab moves focus. Layout only processes data; your component code runs once.", "UI", 15, muted)
	_, err = ui.close_layout()
	assert(err == .None)
	ui.close_clip()
}
