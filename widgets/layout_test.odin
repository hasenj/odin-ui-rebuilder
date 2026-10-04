package widgets

import ui "../core"
import "core:testing"
import "core:path/filepath"

@(private) layout_button_step: int
@(private) layout_button_clicks: [2]int
@(private) layout_button_focus: ui.Identity

// One builder call per frame, through real solving, interaction and rendering.
// Covers content measurements, fixed bounds, label fitting, focus across keyed
// reorder, disabled activation and resizing under narrow constraints.
@(private)
button_layouts :: proc(t: ^testing.T) {
	layout_button_step = 0; layout_button_clicks = {}; test_font = 0
	frames: [8]ui.Capture_Frame
	for &f, i in frames { f = {size = {420, 240}, scale = 2, time = f64(i)*0.1} }
	frames[1].input = {mouse_inside = true, mouse_position = {30, 30}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[2].input = {mouse_inside = true, mouse_position = {30, 30}, mouse_released = {.Left}}
	frames[4].input.keys_pressed = {.Enter}
	frames[5].input.keys_pressed = {.Enter}
	frames[6].size.x = 100
	path, _ := filepath.join({filepath.dir(#location().file_path), "../bin/widget-button-layout.png"})
	defer delete(path)
	frames[3].path = path
	result := ui.capture_frames(layout_button_scene, frames[:])
	testing.expect_value(t, result.error, ui.Capture_Error.None)
	testing.expect_value(t, layout_button_step, len(frames))
	testing.expect_value(t, layout_button_clicks, [2]int{2, 0})
	test_font = 0
}

@(private)
layout_button_scene :: proc() {
	if test_font == 0 {
		path, _ := filepath.join({filepath.dir(#location().file_path), "../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
		defer delete(path)
		err: ui.Text_Error; test_font, err = ui.load_font(path); assert(err == .None)
	}
	begin(test_font)
	ui.paint(color = theme.background); ui.pad(20); ui.open_clip()
	start := len(ui.current_frame().surfaces)
	ui.open_layout(.Top, {flow = .Row, gap = 10})
	labels := [2]string{"Go", "Save all changes"}
	for n in 0..<2 {
		i := 1-n if layout_button_step >= 3 else n
		ui.open_box(key = i)
		if button(labels[i], enabled = layout_button_step != 5, sizing = .Content) { layout_button_clicks[i] += 1 }
		ui.close_box()
	}
	_, err := ui.close_layout(); assert(err == .None)
	count := 0
	for surface in ui.current_frame().surfaces[start:] {
		if surface.border_width != 1 || surface.background != theme.border { continue }
		i := 1-count if layout_button_step >= 3 else count
		metrics, measure_err := ui.measure_text(labels[i], current_font, theme.font_size); assert(measure_err == .None)
		expected_width := min(metrics.width+theme.padding*3, ui.current_frame().size.x-40)
		testing.expect(test_t, abs(surface.size.x-expected_width) < 0.01)
		if layout_button_step != 6 { testing.expect(test_t, abs(surface.size.y-metrics.height-theme.padding*2) < 0.01) }
		count += 1
	}
	testing.expect_value(test_t, count, 2)
	if layout_button_step == 2 { layout_button_focus = ui.direct_focus() }
	if layout_button_step == 4 { testing.expect_value(test_t, ui.direct_focus(), layout_button_focus) }
	ui.pad4(16, 0, 0, 0)
	start = len(ui.current_frame().surfaces)
	ui.open_layout(.Top, {flow = .Row, gap = 10})
	for i in 0..<2 {
		ui.open_box(key = i)
		_ = button("Save all changes", size = {80 if i == 0 else 160, 32})
		ui.close_box()
	}
	_, err = ui.close_layout(); assert(err == .None)
	index := -1
	heights: [2]f32
	for surface in ui.current_frame().surfaces[start:] {
		if surface.border_width == 1 && surface.background == theme.border {
			index += 1
			expected := [2]f32{min(80 if index == 0 else 160, ui.current_frame().size.x-40), 32}
			testing.expect_value(test_t, surface.size, expected)
		} else if surface.image != (ui.Image{}) {
			testing.expect(test_t, surface.clip.enabled)
			heights[index] = max(heights[index], surface.size.y)
		}
	}
	testing.expect_value(test_t, index, 1)
	if layout_button_step != 6 { testing.expect(test_t, heights[0] > 0 && heights[0] < heights[1], "Fixed labels shrink without resizing the button") }
	ui.pad4(16, 0, 0, 0)
	ui.open_rect(.Top, 32)
	_ = button("Default still uses the supplied rectangle")
	ui.close_rect(); ui.close_clip()
	layout_button_step += 1
}
