package app10

import ui "../../core"
import "core:fmt"
import "core:os"

font: ui.Font
capture_mode: bool
show_modal: bool
list_offset: [2]f32
list_id: ui.Identity
button_ids: [12]ui.Identity
modal_ids: [2]ui.Identity
ink :: ui.Color{0.92, 0.95, 1, 1}
muted :: ui.Color{0.58, 0.66, 0.78, 1}

main :: proc() {
	if len(os.args) == 2 && os.args[1] == "--capture" {
		capture_mode = true
		frames := [?]ui.Capture_Frame{
			{path = "bin/app10-initial.png", size = {1000, 760}, scale = 2},
			{size = {1000, 760}, scale = 2, time = 0.01, input = {keys_pressed = {.Tab}}},
			{path = "bin/app10-focus.png", size = {1000, 760}, scale = 2, time = 0.02},
			{size = {1000, 760}, scale = 2, time = 0.03, input = {mouse_inside = true, mouse_position = {80, 240}, scroll_delta = {0, 180}}},
			{path = "bin/app10-scrolled.png", size = {1000, 760}, scale = 2, time = 0.04, input = {mouse_inside = true, mouse_position = {80, 240}}},
			// A new focus target outside the viewport is revealed automatically.
			{path = "bin/app10-reveal.png", size = {1000, 760}, scale = 2, time = 0.05, input = {keys_pressed = {.Tab}}},
			{size = {1000, 760}, scale = 2, time = 1},
			{path = "bin/app10-modal.png", size = {1000, 760}, scale = 2, time = 1.01},
			{path = "bin/app10-modal-tab.png", size = {1000, 760}, scale = 2, time = 1.02, input = {keys_pressed = {.Tab}}},
			{size = {1000, 760}, scale = 2, time = 2},
			{path = "bin/app10-restored.png", size = {1000, 760}, scale = 2, time = 2.01},
			{path = "bin/app10-small.png", size = {760, 480}, scale = 1, time = 2.02},
		}
		result := ui.capture_frames(update, frames[:])
		if result.error != .None { fmt.eprintln(result); os.exit(1) }
		fmt.println("Verified synthetic UI scenarios; captures saved to bin/app10-*.png")
		return
	}
	ui.open_window("Odin UI Rebuilder — UI foundations", 1000, 760, update, frame_timing = .Summary)
}

update :: proc() {
	if font == 0 {
		err: ui.Text_Error
		font, err = ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf")
		assert(err == .None)
	}
	frame := ui.current_frame()
	if capture_mode { show_modal = frame.time >= 1 && frame.time < 2 }
	ui.paint(color = {0.04, 0.055, 0.085, 1})
	ui.open_rect(.Top, 82)
	ui.paint(color = {0.075, 0.10, 0.15, 1})
	ui.pad2(20, 28)
	label("UI foundations", 30, ink, 650)
	ui.close_rect()
	ui.open_rect(.Bottom, 42)
	ui.paint(color = {0.075, 0.10, 0.15, 1})
	ui.pad2(10, 28)
	label("Wheel / trackpad to scroll · Click to focus · Synthetic Tab in capture mode", 14, muted)
	ui.close_rect()
	ui.pad(24)
	ui.open_rect(.Left, min(380, ui.current_rect().size.x * 0.44))
	ui.paint(color = {0.08, 0.105, 0.15, 1}, corners = 16)
	ui.pad(16)
	ui.open_rect(.Top, 42)
	label("SCROLL / HOVER / FOCUS", 15, muted, 650)
	ui.close_rect()
	ui.open_scroll({ui.current_rect().size.x, 12 * 64}, key = 100)
	list_id = ui.current_identity()
	list_offset = ui.current_scroll().offset
	for i in 0..<12 {
		ui.open_rect(.Top, 64, key = i)
		button_ids[i] = ui.current_identity()
		ui.focusable()
		ui.pad4(0, 0, 8, 0)
		button(fmt.tprintf("Item %02d", i + 1))
		ui.close_rect()
	}
	ui.close_scroll()
	ui.close_rect()
	ui.pad4(0, 0, 0, 24)
	ui.open_rect(.Top, 185)
	ui.paint(color = {0.08, 0.105, 0.15, 1}, corners = 16)
	ui.pad(20)
	ui.open_rect(.Top, 36)
	label("TEXT CLIPS AT THE EDGE", 15, muted, 650)
	ui.close_rect()
	ui.open_clip()
	ui.open_offset({-24, -5})
	label("A long line continues beyond its panel.", 32, ink)
	ui.pad4(52, 0, 0, 0)
	label("Clipping belongs to the renderer.", 25, {0.45, 0.77, 0.95, 1})
	ui.close_rect()
	ui.close_clip()
	ui.close_rect()
	ui.pad4(24, 0, 0, 0)
	ui.open_rect(.Top, 235)
	ui.paint(color = {0.08, 0.105, 0.15, 1}, corners = 16)
	ui.open_clip()
	ui.pad(20)
	ui.open_rect(.Top, 36)
	label("LAYERS / STABLE DRAW ORDER", 15, muted, 650)
	ui.close_rect()
	area := ui.current_rect()
	ui.open_layer(2)
	ui.open_rect_at(ui.Rect{area.position + [2]f32{100, 30}, {190, 90}}, key = 200)
	ui.paint(color = {0.48, 0.31, 0.76, 0.95}, corners = 12)
	ui.pad(14)
	label("Layer 2", 23, ink, 650)
	ui.close_rect()
	ui.close_layer()
	// Declared later, but drawn below layer 2.
	ui.open_rect_at(ui.Rect{area.position, {210, 90}}, key = 201)
	ui.paint(color = {0.12, 0.44, 0.53, 1}, corners = 12)
	ui.pad(14)
	label("Layer 0", 23, ink, 650)
	ui.close_rect()
	ui.close_clip()
	ui.close_rect()
	if show_modal { modal() }
	if capture_mode { verify_scenario() }
}

button :: proc(title: string) {
	color := ui.Color{0.13, 0.18, 0.26, 1}
	if ui.hovered() { color = {0.17, 0.34, 0.54, 1} }
	ui.paint(color = {0.98, 0.70, 0.28, 1} if ui.focused() else color, corners = 10)
	ui.pad(3)
	ui.paint(color = color, corners = 8)
	ui.pad2(10, 14)
	label(title, 19, ink, 550)
}

modal :: proc() {
	frame := ui.current_frame()
	ui.open_layer(20, escape_clip = true)
	ui.open_rect_at(ui.Rect{size = frame.size}, key = 300)
	ui.paint(color = {0.01, 0.02, 0.04, 0.72}) // Full-window hit barrier.
	ui.focus_fence()
	ui.open_rect_at(ui.Rect{(frame.size - [2]f32{440, 235}) * 0.5, {440, 235}}, key = 301)
	ui.paint(color = {0.12, 0.15, 0.22, 1}, corners = 18)
	ui.pad(24)
	ui.open_rect(.Top, 46)
	label("A focus fence", 27, ink, 650)
	ui.close_rect()
	ui.open_rect(.Top, 42)
	label("Tab stays here. Closing restores focus.", 17, muted)
	ui.close_rect()
	for i in 0..<2 {
		ui.open_rect(.Left, 190, key = i)
		modal_ids[i] = ui.current_identity()
		ui.focusable()
		button("Continue" if i == 0 else "Cancel")
		ui.close_rect()
	}
	ui.close_rect()
	ui.close_rect()
	ui.close_layer()
}

label :: proc(value: string, size: f32, color: ui.Color, weight: f32 = 0) {
	_, err := ui.text(value, font, size = size, color = color, weight = weight)
	assert(err == .None)
}

verify_scenario :: proc() {
	time := ui.current_frame().time
	if time == 0.02 { assert(ui.direct_focus() == button_ids[0]) }
	if time == 0.04 { assert(list_offset.y == 180) }
	if time == 0.05 { assert(ui.direct_focus() == button_ids[1] && list_offset.y == 64) }
	if time == 1.01 { assert(ui.direct_focus() == modal_ids[0]) }
	if time == 1.02 { assert(ui.direct_focus() == modal_ids[1]) }
	if time == 2.01 { assert(ui.direct_focus() == button_ids[1]) }
}
