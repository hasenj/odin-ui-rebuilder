package demo14

import ui "../../core"
import "core:os"
import "core:fmt"

App :: struct {reverse: bool, show_second: bool, selected: int}
Drag :: struct {offset, grab: [2]f32, dragging: bool}
Button :: struct {pressed: bool}

main :: proc() {
	if len(os.args) > 1 && os.args[1] == "--capture" { capture_check(); return }
	ui.open_window("Retained state — drag and reorder", 740, 540, update, transparent = false, frame_timing = .Summary)
}

update :: proc() {
	app := ui.state(App, proc(value: ^App) { value.show_second = true })
	if _, ok := ui.find_font("UI"); !ok {
		_, err := ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf", "UI")
		assert(err == .None)
	}
	ui.paint(color = {0.06, 0.08, 0.12, 1})
	ui.pad(28)
	ui.open_rect(.Top, 45); label("State follows identity", 28); ui.close_rect()
	ui.open_rect(.Top, 40); label("Overlap the cards, then reverse which one is in front.", 17); ui.close_rect()
	ui.open_rect(.Top, 42)
	ui.open_rect(.Left, 180)
	if button("Reverse draw order") { app.reverse = !app.reverse }
	ui.close_rect()
	ui.pad4(0, 0, 0, 12)
	ui.open_rect(.Left, 190)
	if button("Hide / show second") { app.show_second = !app.show_second }
	ui.close_rect()
	ui.close_rect()
	origin := ui.current_rect().position + [2]f32{0, 30}
	for i in 0..<2 {
		key := 2 - i if app.reverse else i + 1
		if key == 2 && !app.show_second { continue }
		ui.open_identity(key = key)
		drag := ui.state(Drag)
		input := ui.current_frame().input
		// Position belongs to the card; loop order controls painting/hit order only.
		base := origin + [2]f32{0, f32(key - 1) * 120}
		if input.mouse_cancelled { drag.dragging = false }
		if drag.dragging {
			drag.offset = input.mouse_position - drag.grab - base
			if .Left in input.mouse_released || .Left not_in input.mouse_buttons { drag.dragging = false }
		}
		ui.open_rect_at({base + drag.offset, {300, 90}})
		card_ids[key - 1], card_positions[key - 1] = ui.current_identity(), ui.current_bounds().position
		ui.focusable()
		if ui.hovered() && .Left in input.mouse_pressed && !input.mouse_cancelled {
			app.selected = key
			drag.grab = input.mouse_position - (base + drag.offset)
			drag.dragging = .Left in input.mouse_buttons
		}
		ui.paint(color = {0.15, 0.48, 0.49, 1} if key == app.selected else {0.18, 0.24, 0.34, 1}, corners = 12)
		ui.pad(14)
		label(fmt.tprintf("Card %d   /   offset %.0f, %.0f", key, drag.offset.x, drag.offset.y), 18)
		ui.close_rect()
		ui.close_identity()
	}
}

button :: proc(title: string) -> bool {
	value := ui.state(Button)
	input := ui.current_frame().input
	ui.focusable()
	if input.mouse_cancelled { value.pressed = false }
	if ui.hovered() && .Left in input.mouse_pressed { value.pressed = true }
	clicked := value.pressed && ui.hovered() && .Left in input.mouse_released && !input.mouse_cancelled
	if .Left in input.mouse_released { value.pressed = false }
	ui.paint(color = {0.25, 0.35, 0.48, 1} if ui.hovered() else {0.15, 0.21, 0.30, 1}, corners = 7)
	ui.pad2(5, 12)
	label(title, 16)
	return clicked || (ui.focused() && (.Space in input.keys_pressed || .Enter in input.keys_pressed))
}
label :: proc(value: string, size: f32) {
	_, err := ui.text(value, "UI", size = size, color = {0.93, 0.95, 0.98, 1})
	assert(err == .None)
}

capture_step: int
card_ids: [2]ui.Identity
card_positions, before_reverse: [2][2]f32
capture_check :: proc() {
	frames := [?]ui.Capture_Frame{
		{size = {740, 540}, scale = 1},
		{size = {740, 540}, scale = 1, input = {mouse_inside = true, mouse_position = {50, 210}, mouse_pressed = {.Left}, mouse_buttons = {.Left}}},
		{size = {740, 540}, scale = 1, input = {mouse_position = {130, 340}, mouse_buttons = {.Left}}},
		{size = {740, 540}, scale = 1, input = {mouse_position = {130, 340}, mouse_released = {.Left}}, path = "bin/demo14-drag.png"},
		{size = {740, 540}, scale = 1, input = {mouse_inside = true, mouse_position = {60, 130}, mouse_pressed = {.Left}, mouse_released = {.Left}}},
		{size = {740, 540}, scale = 1, input = {mouse_inside = true, mouse_position = {150, 350}}, path = "bin/demo14-reordered.png"},
		{size = {740, 540}, scale = 1, input = {mouse_inside = true, mouse_position = {60, 130}, mouse_pressed = {.Left}, mouse_released = {.Left}}},
		{size = {740, 540}, scale = 1, input = {mouse_inside = true, mouse_position = {150, 350}}},
		{size = {740, 540}, scale = 1},
		{size = {740, 540}, scale = 1},
	}
	result := ui.capture_frames(capture_update, frames[:])
	assert(result.error == .None)
	fmt.println("Verified drag state, outside release, stationary reorder, reversed hit order and removal")
}
capture_update :: proc() {
	app := ui.state(App, proc(value: ^App) { value.show_second = true })
	if capture_step == 8 { app.show_second = false }
	if capture_step == 9 { app.show_second = true }
	update()
	if capture_step == 3 { before_reverse = card_positions }
	if capture_step >= 4 && capture_step <= 7 { assert(card_positions == before_reverse, "Reordering must not move the cards") }
	if capture_step == 5 { assert(app.reverse && ui.direct_hover() == card_ids[0]) }
	if capture_step == 7 { assert(!app.reverse && ui.direct_hover() == card_ids[1]) }
	if capture_step >= 2 { assert(app.selected == 1) }
	capture_step += 1
}
