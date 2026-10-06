package widgets

import ui "../core"
import "core:testing"
import "core:path/filepath"
import "core:image/png"
import "core:image"

@(private) field_test_editor: ui.Text_Edit
@(private) field_test_number: f64
@(private) field_test_step: int

// Shared chrome must not cover button focus. Exercise clearing/refocusing and
// native-style text delivery plus mouse caret placement in centered numbers.
@(private)
compound_fields :: proc(t: ^testing.T) {
	ui.init_text_edit(&field_test_editor, "Files")
	defer ui.destroy_text_edit(&field_test_editor)
	field_test_number = 24; field_test_step = 0; test_font = 0
	path, _ := filepath.join({filepath.dir(#location().file_path), "../bin/widget-fields-focus.png"})
	defer delete(path)
	frames: [14]ui.Capture_Frame
	for &f, i in frames { f = {size = {320, 140}, scale = 2, time = f64(i)*0.1} }
	frames[1].input = {mouse_inside = true, mouse_position = {35, 95}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[2].input = {mouse_inside = true, mouse_position = {35, 95}, mouse_released = {.Left}}
	frames[3].path = path
	frames[4].input = {mouse_inside = true, mouse_position = {120, 35}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[5].input = {mouse_inside = true, mouse_position = {120, 35}, mouse_released = {.Left}}
	frames[7].input = {mouse_inside = true, mouse_position = {285, 35}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[8].input = {mouse_inside = true, mouse_position = {285, 35}, mouse_released = {.Left}}
	frames[10].input = {mouse_inside = true, mouse_position = {80, 95}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[11].input = {mouse_inside = true, mouse_position = {80, 95}, mouse_released = {.Left}}
	result := ui.capture_frames(field_test_scene, frames[:])
	if !testing.expect_value(t, result.error, ui.Capture_Error.None) { return }
	testing.expect_value(t, ui.text_edit_value(&field_test_editor), "new")
	testing.expect_value(t, field_test_number, f64(123))
	decoded, err := png.load(path)
	if testing.expect(t, err == nil) {
		defer image.destroy(decoded)
		// Right edge of the minus button focus ring, next to the editor.
		p := ((95*2)*decoded.width + 47*2)*4
		testing.expect(t, decoded.pixels.buf[p+1] > 120 && decoded.pixels.buf[p] < 80, "Number editor covers the button focus outline")
	}
	test_font = 0
}

@(private)
field_test_scene :: proc() {
	if test_font == 0 {
		path, _ := filepath.join({filepath.dir(#location().file_path), "../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
		defer delete(path)
		err: ui.Text_Error; test_font, err = ui.load_font(path); assert(err == .None)
	}
	begin(test_font)
	if field_test_step == 9 || field_test_step == 12 {
		ui.current_frame().input.text = {target = ui.text_target(ui.direct_focus()), operations = {{kind = .Commit, text = "new" if field_test_step == 9 else "1"}}}
	}
	ui.paint(color = colors.surface)
	ui.open_rect_at({{20, 20}, {280, 30}}); _ = search_field(&field_test_editor, "Find files"); ui.close_rect()
	ui.open_rect_at({{20, 80}, {180, 30}}); _ = number_input(&field_test_number, 0, 1000); ui.close_rect()
	field_test_step += 1
}
