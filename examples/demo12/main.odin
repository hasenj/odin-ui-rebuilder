package demo12

import ui "../../core"
import "core:fmt"
import "core:os"

shared_value: int
windows: [2]ui.Window
previous: [2]ui.Mouse_Buttons
pressed_id: [2]ui.Identity
ink :: ui.Color{0.92, 0.95, 1, 1}
muted :: ui.Color{0.58, 0.67, 0.79, 1}

main :: proc() {
	if len(os.args) == 2 && os.args[1] == "--capture" {
		for update, i in ([2]ui.Update{workspace, inspector}) {
			frames := [?]ui.Capture_Frame{
				{path = fmt.tprintf("bin/demo12-%d.png", i), size = {620, 640}, scale = 2},
				{path = fmt.tprintf("bin/demo12-%d-hover-left.png", i), size = {620, 640}, scale = 2, time = 1,
				 input = {mouse_inside = true, mouse_position = {100, 590}}},
				{path = fmt.tprintf("bin/demo12-%d-hover-right.png", i), size = {620, 640}, scale = 2, time = 2,
				 input = {mouse_inside = true, mouse_position = {480, 590}}},
			}
			assert(ui.capture_frames(update, frames[:]).error == .None)
		}
		// Exercise the actual panel buttons: a sibling must not overwrite the
		// pressed identity or activate when releasing over the other button.
		frames := [?]ui.Capture_Frame{
			{size = {620, 640}, scale = 1},
			{size = {620, 640}, scale = 1, time = 1, input = {mouse_inside = true, mouse_position = {100, 590}, mouse_buttons = {.Left}}},
			{size = {620, 640}, scale = 1, time = 2, input = {mouse_inside = true, mouse_position = {480, 590}}},
			{size = {620, 640}, scale = 1, time = 3, input = {mouse_inside = true, mouse_position = {100, 590}, mouse_buttons = {.Left}}},
			{size = {620, 640}, scale = 1, time = 4, input = {mouse_inside = true, mouse_position = {100, 590}}},
		}
		assert(ui.capture_frames(inspector, frames[:]).error == .None)
		assert(shared_value == 1, "Only the press/release within the Add button should activate it")
		fmt.println("Verified demo12 footer button clicks; hover captures saved to bin/demo12-*-hover-*.png")
		return
	}
	ui.init()
	defer ui.shutdown()
	open(0)
	open(1)
	ui.run()
}

open :: proc(index: int) {
	if ui.window_alive(windows[index]) { return }
	previous[index] = {}
	pressed_id[index] = {}
	if index == 0 {
		windows[index] = ui.create_window("Workspace — demo12", 660, 700, workspace, frame_timing = .Summary)
	} else {
		windows[index] = ui.create_panel("Inspector panel — demo12", 540, 580, inspector, frame_timing = .Summary)
	}
}

workspace :: proc() { draw(0) }
inspector :: proc() { draw(1) }

draw :: proc(index: int) {
	if _, found := ui.find_font("UI"); !found {
		_, err := ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf", "UI")
		assert(err == .None)
	}
	frame := ui.current_frame()
	pressed := frame.input.mouse_pressed | (frame.input.mouse_buttons & ~previous[index])
	released := frame.input.mouse_released | (previous[index] & ~frame.input.mouse_buttons)
	previous[index] = frame.input.mouse_buttons
	if frame.input.mouse_cancelled { pressed, released = {}, {} }
	accent := ui.Color{0.16, 0.36, 0.65, 1} if index == 0 else ui.Color{0.36, 0.23, 0.58, 1}
	ui.paint(color = {0.04, 0.055, 0.085, 1})
	ui.pad(24)
	ui.open_rect(.Top, 46)
	label("Workspace" if index == 0 else "Inspector panel", 30, ink)
	ui.close_rect()
	ui.open_rect(.Top, 55)
	label(fmt.tprintf("Shared update clock: %.2f s", frame.time), 17, muted)
	ui.close_rect()
	ui.open_rect(.Bottom, 62)
	ui.pad4(12, 0, 0, 0)
	ui.open_rect(.Left, ui.current_rect().size.x * 0.60)
	if button("Open panel" if index == 0 else "Add to shared value", index, pressed, released, accent) {
		if index == 0 { open(1) } else { shared_value += 1 }
	}
	ui.close_rect()
	ui.pad4(0, 0, 0, 10)
	// Both buttons need sibling hit regions; the footer itself also covers the left button.
	ui.open_rect(.Left, ui.current_rect().size.x)
	if button("Quit app" if index == 0 else "Close panel", index, pressed, released, accent) {
		if index == 0 { ui.request_close(ui.current_window()) } else { ui.close_panel(ui.current_window()) }
	}
	ui.close_rect()
	ui.close_rect()
	ui.open_rect(.Bottom, 44)
	ui.pad4(12, 0, 0, 0)
	label(fmt.tprintf("Shared value: %d · Wheel / Tab / Enter", shared_value), 15, muted)
	ui.close_rect()
	ui.paint(color = {0.075, 0.095, 0.14, 1}, corners = 14)
	ui.pad(12)
	ui.open_scroll({ui.current_rect().size.x, 20 * 58})
	for i in 0..<20 {
		ui.open_rect(.Top, 58, key = i)
		ui.pad4(0, 0, 6, 0)
		button(fmt.tprintf("%s %02d", "Document" if index == 0 else "Property", i + 1), index, pressed, released, accent)
		ui.close_rect()
	}
	ui.close_scroll()
	if .Left in released { pressed_id[index] = {} }
}

button :: proc(title: string, index: int, pressed, released: ui.Mouse_Buttons, accent: ui.Color) -> bool {
	ui.focusable()
	id := ui.current_identity()
	hover := ui.hovered()
	if hover && .Left in pressed { pressed_id[index] = id }
	clicked := hover && pressed_id[index] == id && .Left in released
	if ui.direct_focus() == id && .Enter in ui.current_frame().input.keys_pressed { clicked = true }
	t := ui.animate_f32(1 if hover else 0)
	base := ui.Color{0.11, 0.14, 0.20, 1}
	color := base + (accent - base) * t
	ui.paint(color = {0.97, 0.70, 0.30, 1} if ui.focused() else color, corners = 9)
	ui.pad(2)
	ui.paint(color = color, corners = 7)
	ui.pad(8)
	layout, err := ui.layout_text_fit(title, "UI", ui.current_rect().size.x, 18, max_height = ui.current_rect().size.y)
	assert(err == .None)
	assert(ui.draw_text_layout(layout, ink, .Center, .Center) == .None)
	return clicked
}

label :: proc(value: string, size: f32, color: ui.Color) {
	layout, err := ui.layout_text_fit(value, "UI", ui.current_rect().size.x, size, max_height = ui.current_rect().size.y)
	assert(err == .None)
	assert(ui.draw_text_layout(layout, color) == .None)
}
