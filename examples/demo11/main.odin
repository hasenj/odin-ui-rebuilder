package demo11

import ui "../../core"
import "core:fmt"
import "core:os"
import "core:strings"

font: ui.Font
last_pressed, last_released: ui.Keys
press_time, release_time: f64 = -1, -1

main :: proc() {
	if len(os.args) == 2 && os.args[1] == "--capture" {
		result := ui.capture_frames(update, []ui.Capture_Frame{
			{size = {1160, 860}, scale = 2, input = {
				keys_down = {.LeftShift, .A, .Digit1, .Keypad1, .F5},
				keys_pressed = {.LeftShift, .A, .Digit1, .Keypad1, .F5}, modifiers = {.Shift},
			}},
			{path = "bin/demo11-held.png", size = {1160, 860}, scale = 2, time = 0.25, input = {
				keys_down = {.LeftShift, .A, .Digit1, .Keypad1, .F5}, modifiers = {.Shift},
			}},
			{path = "bin/demo11-released.png", size = {1160, 860}, scale = 2, time = 0.35, input = {
				keys_released = {.LeftShift, .A, .Digit1, .Keypad1, .F5},
			}},
		})
		assert(result.error == .None)
		return
	}
	ui.open_window("Odin UI Rebuilder — Keyboard input", 1160, 860, update, frame_timing = .Summary)
}

update :: proc() {
	if font == 0 {
		err: ui.Text_Error
		font, err = ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf")
		assert(err == .None)
	}
	frame := ui.current_frame()
	input := frame.input
	if input.keys_pressed != (ui.Keys{}) { last_pressed, press_time = input.keys_pressed, frame.time }
	if input.keys_released != (ui.Keys{}) { last_released, release_time = input.keys_released, frame.time }
	ui.paint(color = {0.04, 0.055, 0.085, 1})
	ui.pad(24)
	line("Keyboard input", 34, {0.94, 0.96, 1, 1}, 48)
	line("Physical keys / US labels. Shift and keyboard layout do not change key identity.", 16, {0.6, 0.7, 0.82, 1}, 32)
	line(fmt.tprintf("Held: %s", format_set(input.keys_down)), 18, {0.38, 0.78, 1, 1}, 34)
	line(fmt.tprintf("Last pressed: %s", format_set(last_pressed)), 18, {1, 0.73, 0.34, 1}, 34)
	line(fmt.tprintf("Last released: %s", format_set(last_released)), 18, {0.78, 0.61, 0.96, 1}, 34)
	line(fmt.tprintf("Modifiers: %s     Locks: %s", format_set(input.modifiers), format_set(input.locks)), 16, {0.7, 0.77, 0.88, 1}, 34)
	ui.open_rect(.Bottom, 40)
	ui.pad4(12, 0, 0, 0)
	text_line("Blue: held · Amber: press · Purple: release · Some hardware/system keys may be intercepted by the OS.", 14, {0.6, 0.7, 0.82, 1})
	ui.close_rect()
	ui.pad4(8, 0, 0, 0)
	width := ui.current_rect().size.x
	columns := max(int(width / 100), 1)
	count := int(max(ui.Key)) + 1
	rows := (count + columns - 1) / columns
	ui.open_scroll({width, f32(rows * 44)}, key = 1)
	for row in 0..<rows {
		ui.open_rect(.Top, 44, key = row)
		for column in 0..<columns {
			index := row * columns + column
			if index >= count { break }
			key := ui.Key(index)
			ui.open_rect(.Left, width / f32(columns), key = index)
			ui.pad2(3, 3)
			color := ui.Color{0.10, 0.14, 0.21, 1}
			if key in input.keys_down { color = {0.10, 0.34, 0.54, 1} }
			if key in last_pressed && frame.time - press_time < 0.15 { color = {0.48, 0.30, 0.10, 1} }
			if key in last_released && key not_in input.keys_down && frame.time - release_time < 0.25 { color = {0.36, 0.23, 0.49, 1} }
			ui.paint(color = color, corners = 6)
			ui.pad(5)
			text_line(fmt.tprintf("%v", key), 14, {0.88, 0.93, 1, 1})
			ui.close_rect()
		}
		ui.close_rect()
	}
	ui.close_scroll()
}

format_set :: proc(values: $T) -> string {
	if values == (T{}) { return "—" }
	builder := strings.builder_make(allocator = context.temp_allocator)
	first := true
	for value in values {
		if !first { strings.write_string(&builder, ", ") }
		first = false
		strings.write_string(&builder, fmt.tprintf("%v", value))
	}
	return strings.to_string(builder)
}

line :: proc(value: string, size: f32, color: ui.Color, height: f32) {
	ui.open_rect(.Top, height)
	text_line(value, size, color)
	ui.close_rect()
}

text_line :: proc(value: string, size: f32, color: ui.Color) {
	bounds := ui.current_rect()
	if bounds.size.x <= 0 || bounds.size.y <= 0 { return }
	layout, err := ui.layout_text_fit(value, font, max_width = bounds.size.x,
		size = size, min_scale = 0.5, max_height = bounds.size.y)
	assert(err == .None)
	ui.open_clip()
	err = ui.draw_text_layout(layout, color, valign = .Center)
	ui.close_clip()
	assert(err == .None)
}
