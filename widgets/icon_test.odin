package widgets

import ui "../core"
import "core:testing"
import "core:path/filepath"
import "core:fmt"
import "core:image/png"
import "core:image"

@(private) icon_test_clicks: [3]int
@(private) icon_test_custom: ui.Icon_Glyph

// Real atlas -> GPU -> PNG at 1x/2x, plus the same press/release and keyboard
// behavior for text+icon, icon-only, and content-sized buttons.
@(private)
icon_widgets :: proc(t: ^testing.T) {
	for scale in 1..=2 {
		test_font = 0; icon_test_clicks = {}
		path, _ := filepath.join({filepath.dir(#location().file_path), "../bin", fmt.tprintf("widget-icons-%dx.png", scale)})
		defer delete(path)
		frames: [10]ui.Capture_Frame
		for &f, i in frames { f = {size = {400, 180}, scale = f32(scale), time = f64(i)*0.1} }
		frames[1].input = {mouse_inside = true, mouse_position = {35, 75}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
		frames[2].input = {mouse_inside = true, mouse_position = {35, 75}, mouse_released = {.Left}}
		frames[3].input = {mouse_inside = true, mouse_position = {200, 75}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
		frames[4].input = {mouse_inside = true, mouse_position = {200, 75}, mouse_released = {.Left}}
		frames[5].input = {keys_down = {.Space}, keys_pressed = {.Space}}
		frames[6].input.keys_released = {.Space}
		frames[7].input = {mouse_inside = true, mouse_position = {30, 125}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
		frames[8].input = {mouse_inside = true, mouse_position = {30, 125}, mouse_released = {.Left}}
		frames[9].path = path
		result := ui.capture_frames(icon_widget_scene, frames[:])
		if !testing.expect_value(t, result.error, ui.Capture_Error.None) { return }
		testing.expect_value(t, icon_test_clicks, [3]int{1, 2, 1})
		decoded, err := png.load(path)
		if !testing.expect(t, err == nil) { continue }
		defer image.destroy(decoded)
		// Transparent background lets us inspect actual antialiased coverage.
		for n in 0..<10 {
			partial, visible := 0, 0
			for y in 16*scale..<40*scale {
				for x in (16+n*36)*scale..<(40+n*36)*scale {
					a := decoded.pixels.buf[(y*decoded.width+x)*4+3]
					if a > 0 { visible += 1 }
					if a > 0 && a < 255 { partial += 1 }
				}
			}
			testing.expect(t, visible > 8 && partial > 4, "Icon must render smoothly at both scales")
		}
	}
	test_font = 0
}

@(private)
icon_widget_scene :: proc() {
	if test_font == 0 {
		path, _ := filepath.join({filepath.dir(#location().file_path), "../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
		defer delete(path)
		err: ui.Text_Error; test_font, err = ui.load_font(path); assert(err == .None)
		// A glyph from an unrelated font works with the same button API.
		icon_test_custom, err = ui.resolve_icon(test_font, 'X'); assert(err == .None)
	}
	begin(test_font)
	for name in Icon {
		start := len(ui.current_frame().surfaces)
		err := ui.draw_icon(icon(name), {{20+f32(int(name))*36, 20}, {16, 16}})
		assert(err == .None)
		testing.expect_value(test_t, len(ui.current_frame().surfaces)-start, 1)
	}
	ui.open_rect_at({{20, 60}, {140, 30}})
	if button("Add item", icon = icon(.Plus)) { icon_test_clicks[0] += 1 }
	ui.close_rect()
	ui.open_rect_at({{180, 60}, {40, 30}})
	if button("", icon = icon_test_custom) { icon_test_clicks[1] += 1 }
	ui.close_rect()
	ui.open_rect_at({{240, 60}, {40, 30}})
	_ = button("", enabled = false, icon = icon(.Close)); ui.close_rect()
	ui.open_rect_at({{20, 110}, {340, 60}})
	ui.open_layout(.Left, {flow = .Row, gap = 12})
	if button("Add", sizing = .Content, icon = icon(.Plus)) { icon_test_clicks[2] += 1 }
	_ = button("", sizing = .Content, icon = icon(.Check))
	_ = button("Search", size = {100, 32}, icon = icon(.Search))
	_, err := ui.close_layout(); assert(err == .None)
	ui.close_rect()
}
