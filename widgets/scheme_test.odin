package widgets

import ui "../core"
import "core:testing"
import "core:path/filepath"
import "core:fmt"
import "core:image/png"
import "core:image"

@(private) scheme_step: int
@(private) scheme_focus: ui.Identity
@(private) scheme_editor: ui.Text_Edit
@(private) scheme_geometry: [dynamic]ui.Surface

// Change schemes while an editor owns focus, and switch three times inside one
// deferred layout. Read actual GPU pixels at both scales and compare geometry.
@(private)
color_schemes :: proc(t: ^testing.T) {
	for scale in 1..=2 {
		test_font = 0; scheme_step = 0; scheme_focus = {}; scheme_geometry = {}
		ui.init_text_edit(&scheme_editor, "Keep")
		paths: [3]string
		for &path, i in paths {
			path, _ = filepath.join({filepath.dir(#location().file_path), "../bin", fmt.tprintf("widget-schemes-%dx-%d.png", scale, i)})
		}
		frames: [5]ui.Capture_Frame
		for &f, i in frames { f = {size = {400, 280}, scale = f32(scale), time = f64(i)} }
		frames[1].input = {mouse_inside = true, mouse_position = {32, 65}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}
		frames[2].input.mouse_released = {.Left}
		frames[1].path = paths[0]; frames[3].path = paths[1]; frames[4].path = paths[2]
		result := ui.capture_frames(scheme_scene, frames[:])
		testing.expect_value(t, result.error, ui.Capture_Error.None)
		testing.expect_value(t, ui.text_edit_value(&scheme_editor), "Retained")
		ui.destroy_text_edit(&scheme_editor); delete(scheme_geometry)
		for path, index in paths {
			decoded, err := png.load(path)
			if testing.expect(t, err == nil) {
				palette := light if index == 1 else dark
				points := [?][2]int{{390, 270}, {30, 20}, {150, 65}, {223, 65}, {30, 150}, {140, 150}, {250, 150}, {30, 210}}
				expected := [?]ui.Color{palette.background, palette.primary, palette.field, palette.thumb, dark.primary, light.primary, {0.6, 0.1, 0.7, 1}, palette.primary}
				for point, n in points {
					p := ((point.y*scale)*decoded.width+point.x*scale)*4
					for channel in 0..<4 {
						testing.expect(t, abs(f32(decoded.pixels.buf[p+channel])/255-expected[n][channel]) < 0.012,
							fmt.tprintf("Scheme pixel %d differs at scale %d, capture %d", n, scale, index))
					}
				}
				image.destroy(decoded)
			}
			delete(path)
		}
	}
	test_font = 0
}

@(private)
scheme_scene :: proc() {
	if test_font == 0 {
		path, _ := filepath.join({filepath.dir(#location().file_path), "../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
		defer delete(path)
		err: ui.Text_Error; test_font, err = ui.load_font(path); assert(err == .None)
	}
	palette := light if scheme_step == 2 || scheme_step == 3 else dark
	begin(test_font, scheme = palette)
	testing.expect_value(test_t, colors, palette) // begin resets the previous build's override.
	if scheme_step == 1 { scheme_focus = ui.direct_focus(); testing.expect(test_t, scheme_focus != (ui.Identity{})) }
	if scheme_step >= 2 { testing.expect_value(test_t, ui.direct_focus(), scheme_focus) }
	if scheme_step == 2 {
		ui.current_frame().input.text = {target = ui.text_target(ui.direct_focus()), operations = {{kind = .Commit, text = "Retained", replacement = {0, 4}, has_replacement = true}}}
	}
	ui.paint(color = colors.background)
	ui.open_rect_at({{20, 10}, {160, 30}}); _ = button("Save", .Primary); ui.close_rect()
	ui.open_rect_at({{20, 50}, {160, 30}}); _ = text_field(&scheme_editor); ui.close_rect()
	checked := true
	ui.open_rect_at({{200, 50}, {160, 30}}); _ = toggle("Checked", &checked); ui.close_rect()
	ui.open_rect_at({{20, 140}, {360, 40}})
	start := len(ui.current_frame().surfaces)
	ui.open_layout(.Left, {flow = .Row, gap = 10})
	for i in 0..<3 {
		colors = dark if i == 0 else light
		if i == 2 { colors.primary = {0.6, 0.1, 0.7, 1} }
		_ = button("Same", .Primary, size = {100, 30})
	}
	// Restore BEFORE layout resolution: recorded commands must own their colors.
	colors = palette
	_, err := ui.close_layout(); assert(err == .None)
	built := ui.current_frame().surfaces[start:]
	if scheme_step == 1 { append(&scheme_geometry, ..built) }
	if scheme_step >= 2 && testing.expect_value(test_t, len(built), len(scheme_geometry)) {
		for surface, i in built {
			testing.expect_value(test_t, surface.position, scheme_geometry[i].position)
			testing.expect_value(test_t, surface.size, scheme_geometry[i].size)
		}
	}
	ui.close_rect()
	ui.open_rect_at({{20, 200}, {160, 30}}); _ = button("Restored", .Primary); ui.close_rect()
	colors = light // Deliberately leave a different scheme for the next begin.
	scheme_step += 1
}
