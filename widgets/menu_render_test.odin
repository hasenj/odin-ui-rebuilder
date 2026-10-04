package widgets

import ui "../core"
import "core:testing"
import "core:path/filepath"
import "core:image/png"
import "core:image"
import "core:fmt"

// Run serially after the interaction sequence: exercise the actual menu scroll
// clip, focus navigation, ancestor clip escape and GPU output at both scales.
@(private)
menu_rendering :: proc(t: ^testing.T) {
	for scale in 1..=2 {
		paths: [2]string
		for &path, i in paths {
			path, _ = filepath.join({filepath.dir(#location().file_path), "../bin", fmt.tprintf("widget-menu-%dx-%d.png", scale, i)})
		}
		defer for path in paths { delete(path) }
		test_font = 0
		frames := [?]ui.Capture_Frame{
			{size = {240, 200}, scale = f32(scale)},
			{size = {240, 200}, scale = f32(scale), path = paths[0]},
			{size = {240, 200}, scale = f32(scale), input = {keys_pressed = {.End}}},
			{size = {240, 200}, scale = f32(scale), path = paths[1]},
		}
		result := ui.capture_frames(menu_render_scene, frames[:])
		if !testing.expect_value(t, result.error, ui.Capture_Error.None) { return }
		for path, i in paths {
			decoded, err := png.load(path)
			if !testing.expect(t, err == nil) { continue }
			defer image.destroy(decoded)
			pixels := decoded.pixels.buf[:]
			// Both horizontal edges must survive the content viewport clip, even
			// for its first and last row. Sample away from text and rounded ends.
			for y in ([2]int{49+i*60, 76+i*60}) {
				p := ((y*scale)*decoded.width + 110*scale)*4
				testing.expect(t, pixels[p+1] > 120 && pixels[p] < 80, "Menu focus outline is clipped")
			}
			// Shadow must remain visible outside the parent's clip and popup.
			near := ((90*scale)*decoded.width + 37*scale)*4
			far := ((90*scale)*decoded.width + 4*scale)*4
			testing.expect(t, int(pixels[far+1])-int(pixels[near+1]) >= 8, "Popup shadow needs visible separation outside the parent clip")
		}
	}
	test_font = 0
}

@(private)
menu_render_scene :: proc() {
	if test_font == 0 {
		path, _ := filepath.join({filepath.dir(#location().file_path), "../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
		defer delete(path)
		err: ui.Text_Error; test_font, err = ui.load_font(path); assert(err == .None)
	}
	begin(test_font)
	ui.paint(color = theme.surface)
	ui.open_rect_at({{40, 40}, {160, 106}})
	ui.open_clip()
	visible := true
	if menu_open(&visible, {{40, 16}, {160, 20}}, {160, 106}) {
		for item in ([]string{"Name", "Kind", "Size"}) { _ = menu_item(item) }
		menu_close()
	}
	ui.close_clip(); ui.close_rect()
}
