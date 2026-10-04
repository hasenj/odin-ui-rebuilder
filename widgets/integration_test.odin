package widgets

import ui "../core"
import "core:testing"
import "core:path/filepath"

@(private) test_step, test_clicks, test_selected, test_tab: int
@(private) test_check, test_modal, test_menu, test_submenu: bool
@(private) keyed_clicks: [2]int
@(private) Test_Key :: distinct int
@(private) test_amount, test_scroll_offset: f32
@(private) test_number: f64 = 24
@(private) test_radio: int
@(private) test_editor: ui.Text_Edit
@(private) test_font: ui.Font
@(private) test_t: ^testing.T

// Public widget APIs -> identity/focus/input pipeline -> real GPU renderer.
// Sequence covers cancelled presses, hold/release, drag outside bounds, editor
// delivery, disabled controls, menu keyboard selection and modal dismissal.
@(test)
widget_interactions :: proc(t: ^testing.T) {
	test_t = t
	test_step, test_clicks, test_selected, test_tab = 0, 0, 0, 0
	test_check, test_modal = false, false; test_amount = 0; test_font = 0
	ui.init_text_edit(&test_editor); defer ui.destroy_text_edit(&test_editor)
	frames: [73]ui.Capture_Frame
	for &frame, i in frames { frame = {size = {360, 340}, scale = 1, time = f64(i)*0.1} }
	frames[1].input = {mouse_inside = true, mouse_position = {20, 20}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[2].input = {mouse_inside = true, mouse_position = {300, 300}, mouse_released = {.Left}}
	frames[3].input = frames[1].input
	frames[4].input = {mouse_inside = true, mouse_position = {20, 20}, mouse_released = {.Left}}
	frames[5].input = {mouse_inside = true, mouse_position = {20, 60}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[6].input = {mouse_inside = true, mouse_position = {20, 60}, mouse_released = {.Left}}
	frames[7].input = {mouse_inside = true, mouse_position = {20, 105}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[8].input = {mouse_inside = true, mouse_position = {250, 105}, mouse_buttons = {.Left}}
	frames[9].input = {mouse_inside = true, mouse_position = {250, 105}, mouse_released = {.Left}}
	frames[10].input = {mouse_inside = true, mouse_position = {20, 145}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[11].input = {mouse_inside = true, mouse_position = {20, 145}, mouse_released = {.Left}}
	frames[13].input = {mouse_inside = true, mouse_position = {20, 185}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[14].input = {mouse_inside = true, mouse_position = {20, 185}, mouse_released = {.Left}}
	frames[15].input = {mouse_inside = true, mouse_position = {20, 225}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[16].input = {mouse_inside = true, mouse_position = {20, 225}, mouse_released = {.Left}}
	frames[18].input.keys_pressed = {.Down}
	frames[19].input.keys_pressed = {.Enter}
	frames[21].input = {mouse_inside = true, mouse_position = {20, 265}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[22].input = {mouse_inside = true, mouse_position = {20, 265}, mouse_released = {.Left}}
	frames[24].input.keys_pressed = {.Tab}
	frames[25].input.keys_pressed = {.Escape}
	frames[27].input = {mouse_inside = true, mouse_position = {180, 20}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[28].input = {mouse_inside = true, mouse_position = {180, 20}, mouse_released = {.Left}}
	frames[29].input.keys_pressed = {.Right}
	frames[30].input.keys_pressed = {.Right}
	frames[31].input.keys_pressed = {.Left}
	frames[32].input = {mouse_inside = true, mouse_position = {50, 105}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[33].input = {mouse_cancelled = true, mouse_buttons = {.Left}}
	frames[34].input = {mouse_inside = true, mouse_position = {250, 105}, mouse_buttons = {.Left}}
	frames[35].input.mouse_released = {.Left}
	frames[36].input = frames[1].input
	frames[37].input = frames[4].input
	frames[38].input = {keys_down = {.Space}, keys_pressed = {.Space}}
	frames[39].input.keys_down = {.Space}
	frames[40].input.keys_released = {.Space}
	frames[41].input = {mouse_inside = true, mouse_position = {200, 90}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[42].input = {mouse_inside = true, mouse_position = {200, 90}, mouse_released = {.Left}}
	frames[43].input = frames[41].input
	frames[45].input = frames[42].input
	frames[47].input.keys_pressed = {.Right}
	frames[49].input.keys_pressed = {.Escape}
	frames[50].input.keys_pressed = {.Escape}
	frames[54].input = frames[1].input
	frames[55].input = frames[4].input
	frames[59].input = {mouse_inside = true, mouse_position = {185, 255}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[60].input = {mouse_inside = true, mouse_position = {185, 255}, mouse_released = {.Left}}
	frames[61].input.keys_pressed = {.Left}
	frames[62].input = {mouse_inside = true, mouse_position = {295, 185}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[63].input = {mouse_inside = true, mouse_position = {295, 185}, mouse_released = {.Left}}
	frames[64].input = {mouse_inside = true, mouse_position = {220, 185}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[65].input = {mouse_inside = true, mouse_position = {220, 185}, mouse_released = {.Left}}
	frames[68].input = frames[1].input
	frames[69].input = {mouse_inside = true, mouse_position = {345, 100}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
	frames[70].input = {mouse_inside = false, mouse_position = {345, 400}, mouse_buttons = {.Left}}
	frames[71].input = {mouse_inside = false, mouse_position = {345, 400}, mouse_released = {.Left}}
	result := ui.capture_frames(test_scene, frames[:])
	testing.expect_value(t, result.error, ui.Capture_Error.None)
	testing.expect_value(t, test_step, len(frames))
	menu_rendering(t)
}

@(private)
test_scene :: proc() {
	if test_font == 0 {
		path, _ := filepath.join({filepath.dir(#location().file_path), "../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
		defer delete(path)
		err: ui.Text_Error; test_font, err = ui.load_font(path); assert(err == .None)
	}
	begin(test_font)
	if test_step == 12 {
		ui.current_frame().input.text = {target = ui.text_target(ui.direct_focus()), operations = {{kind = .Commit, text = "hello"}}}
	}
	if test_step == 66 || test_step == 67 {
		ui.current_frame().input.text = {target = ui.text_target(ui.direct_focus()), operations = {{kind = .Commit, text = "42" if test_step == 66 else "bad", replacement = {0, 2}, has_replacement = true}}}
	}
	ui.paint(color = theme.background)
	ui.open_rect_at({{10, 10}, {120, 30}}); if button("Run") { test_clicks += 1 }; ui.close_rect()
	ui.open_rect_at({{10, 50}, {120, 30}}); _ = checkbox("Enabled", &test_check); ui.close_rect()
	ui.open_rect_at({{10, 90}, {120, 30}}); _ = slider(&test_amount); ui.close_rect()
	ui.open_rect_at({{10, 130}, {120, 30}}); _ = text_field(&test_editor); ui.close_rect()
	ui.open_rect_at({{10, 170}, {120, 30}}); if button("Disabled", enabled = false) { test_clicks += 100 }; ui.close_rect()
	ui.open_rect_at({{10, 210}, {120, 30}}); _ = dropdown({"Name", "Size", "Kind"}, &test_selected); ui.close_rect()
	ui.open_rect_at({{10, 250}, {120, 30}}); if button("Dialog") { test_modal = true }; ui.close_rect()
	ui.open_rect_at({{160, 10}, {190, 30}}); _ = tabs({"One", "Two", "Three"}, &test_tab); ui.close_rect()
	for n in 0..<2 {
		index := 1-n if test_step >= 42 else n
		if test_step == 44 && index == 0 { continue }
		ui.open_identity(key = Test_Key(index))
		ui.open_rect_at({{180, 80+f32(index)*40}, {140, 30}})
		if button("Keyed") { keyed_clicks[index] += 1 }
		ui.close_rect(); ui.close_identity()
	}
	ui.open_rect_at({{160, 170}, {150, 30}}); _ = number_input(&test_number, 0, 100); ui.close_rect()
	ui.open_rect_at({{160, 210}, {150, 60}}); _ = radio_group({"First", "Second"}, &test_radio); ui.close_rect()
	ui.open_rect_at({{320, 90}, {30, 190}})
	ui.open_scroll({30, 1000}); scrollbar(); test_scroll_offset = ui.current_scroll().offset.y; ui.close_scroll(); ui.close_rect()
	if test_step == 46 || test_step == 52 { test_menu = true }
	if menu_open(&test_menu, {{170, 150}, {100, 30}}, {150, 90}) {
		if submenu_open("Submenu", &test_submenu, {100, 60}) {
			_ = menu_item("Child")
			submenu_close()
		}
		_ = menu_item("Other")
		menu_close()
	}
	if dialog_open("Modal", &test_modal, {230, 130}) {
		ui.open_rect(.Top, 30); if button("Done") { test_modal = false }; ui.close_rect()
		dialog_close()
	}
	switch test_step {
	case 2: testing.expect_value(test_t, test_clicks, 0)
	case 4: testing.expect_value(test_t, test_clicks, 1)
	case 6: testing.expect(test_t, test_check)
	case 8, 9: testing.expect_value(test_t, test_amount, f32(1))
	case 12: testing.expect_value(test_t, ui.text_edit_value(&test_editor), "hello")
	case 14: testing.expect_value(test_t, test_clicks, 1)
	case 19: testing.expect_value(test_t, test_selected, 1)
	case 23: testing.expect(test_t, test_modal)
	case 25: testing.expect(test_t, !test_modal)
	case 29: testing.expect_value(test_t, test_tab, 1)
	case 30: testing.expect_value(test_t, test_tab, 2)
	case 31: testing.expect_value(test_t, test_tab, 1)
	case 34: testing.expect(test_t, test_amount > 0.2 && test_amount < 0.5)
	case 39: testing.expect_value(test_t, test_clicks, 2)
	case 40: testing.expect_value(test_t, test_clicks, 3)
	case 42: testing.expect_value(test_t, keyed_clicks[0], 1)
	case 45: testing.expect_value(test_t, keyed_clicks[0], 1)
	case 48: testing.expect(test_t, test_menu && test_submenu)
	case 49: testing.expect(test_t, test_menu && !test_submenu)
	case 50: testing.expect(test_t, !test_menu)
	case 54: testing.expect(test_t, !test_menu)
	case 55: testing.expect_value(test_t, test_clicks, 3)
	case 60: testing.expect_value(test_t, test_radio, 1)
	case 61: testing.expect_value(test_t, test_radio, 0)
	case 63: testing.expect_value(test_t, test_number, f64(25))
	case 66, 67, 68: testing.expect_value(test_t, test_number, f64(42))
	case 70, 71: testing.expect(test_t, test_scroll_offset > 800)
	}
	test_step += 1
}
