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
opener_id, pressed_button: ui.Identity
previous_buttons, pressed, released: ui.Mouse_Buttons
ink :: ui.Color{0.92, 0.95, 1, 1}
muted :: ui.Color{0.58, 0.66, 0.78, 1}

main :: proc() {
	if len(os.args) == 2 && os.args[1] == "--capture" {
		capture_mode = true
		frames := [?]ui.Capture_Frame{
			{path = "bin/app10-initial.png", size = {1000, 760}, scale = 2},
			{size = {1000, 760}, scale = 2, time = 0.01, input = {mouse_inside = true, mouse_position = {80, 190}, mouse_buttons = {.Left}}},
			{path = "bin/app10-focus.png", size = {1000, 760}, scale = 2, time = 0.02, input = {mouse_inside = true, mouse_position = {80, 190}}},
			{size = {1000, 760}, scale = 2, time = 0.03, input = {mouse_inside = true, mouse_position = {80, 240}, scroll_delta = {0, 180}}},
			{path = "bin/app10-scrolled.png", size = {1000, 760}, scale = 2, time = 0.04, input = {mouse_inside = true, mouse_position = {80, 240}}},
			// A new focus target outside the viewport is revealed automatically.
			{path = "bin/app10-reveal.png", size = {1000, 760}, scale = 2, time = 0.05, input = {keys_pressed = {.Tab}}},
			// Pressing the opener, then releasing outside, must not activate it.
			{size = {1000, 760}, scale = 2, time = 0.06, input = {mouse_inside = true, mouse_position = {890, 40}, mouse_buttons = {.Left}}},
			{size = {1000, 760}, scale = 2, time = 0.07, input = {mouse_inside = true, mouse_position = {750, 110}}},
			// An ordinary click opens the modal on release, not while held.
			{size = {1000, 760}, scale = 2, time = 1, input = {mouse_inside = true, mouse_position = {890, 40}, mouse_buttons = {.Left}}},
			{size = {1000, 760}, scale = 2, time = 1.001, input = {mouse_inside = true, mouse_position = {890, 40}, mouse_buttons = {.Left}}},
			{size = {1000, 760}, scale = 2, time = 1.005, input = {mouse_inside = true, mouse_position = {890, 40}}},
			{path = "bin/app10-modal.png", size = {1000, 760}, scale = 2, time = 1.01},
			{path = "bin/app10-modal-tab.png", size = {1000, 760}, scale = 2, time = 1.02, input = {keys_pressed = {.Tab}}},
			// The overlay blocks clicks and scrolling from reaching the list.
			{size = {1000, 760}, scale = 2, time = 1.03, input = {mouse_inside = true, mouse_position = {80, 200}, mouse_buttons = {.Left}, scroll_delta = {0, 90}}},
			{size = {1000, 760}, scale = 2, time = 1.04},
			{size = {1000, 760}, scale = 2, time = 2, input = {mouse_inside = true, mouse_position = {590, 420}, mouse_buttons = {.Left}}},
			{size = {1000, 760}, scale = 2, time = 2.005, input = {mouse_inside = true, mouse_position = {590, 420}}},
			{size = {1000, 760}, scale = 2, time = 2.006},
			{path = "bin/app10-restored.png", size = {1000, 760}, scale = 2, time = 2.01},
			// Reopen and close with Continue too.
			{size = {1000, 760}, scale = 2, time = 2.1, input = {mouse_inside = true, mouse_position = {890, 40}, mouse_buttons = {.Left}}},
			{size = {1000, 760}, scale = 2, time = 2.11, input = {mouse_inside = true, mouse_position = {890, 40}}},
			{size = {1000, 760}, scale = 2, time = 2.12},
			{size = {1000, 760}, scale = 2, time = 2.13, input = {mouse_inside = true, mouse_position = {400, 420}, mouse_buttons = {.Left}}},
			{size = {1000, 760}, scale = 2, time = 2.14, input = {mouse_inside = true, mouse_position = {400, 420}}},
			{size = {1000, 760}, scale = 2, time = 2.15},
			{size = {1000, 760}, scale = 2, time = 2.16},
			{path = "bin/app10-small.png", size = {760, 480}, scale = 1, time = 2.2},
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
	pressed = frame.input.mouse_pressed | (frame.input.mouse_buttons & ~previous_buttons)
	released = frame.input.mouse_released | (previous_buttons & ~frame.input.mouse_buttons)
	previous_buttons = frame.input.mouse_buttons
	ui.paint(color = {0.04, 0.055, 0.085, 1})
	ui.open_rect(.Top, 82)
	ui.paint(color = {0.075, 0.10, 0.15, 1})
	ui.pad2(20, 28)
	ui.open_rect(.Right, 160, key = 400)
	opener_id = ui.current_identity()
	ui.focusable()
	if button("Open modal") { show_modal = true }
	ui.close_rect()
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
	if .Left in released { pressed_button = {} }
	if capture_mode { verify_scenario() }
}

// Sample-local activation state: press inside, then release inside. Hover uses
// resolved layer-aware hits, so an overlay cannot activate a covered button.
button :: proc(title: string) -> bool {
	id := ui.current_identity()
	hovered := ui.hovered()
	if hovered && .Left in pressed { pressed_button = id }
	activated := hovered && pressed_button == id && .Left in released
	color := ui.Color{0.13, 0.18, 0.26, 1}
	if hovered { color = {0.17, 0.34, 0.54, 1} }
	if hovered && pressed_button == id && .Left in ui.current_frame().input.mouse_buttons {
		color = {0.10, 0.24, 0.40, 1}
	}
	ui.paint(color = {0.98, 0.70, 0.28, 1} if ui.focused() else color, corners = 10)
	ui.pad(3)
	ui.paint(color = color, corners = 8)
	ui.pad2(10, 14)
	label(title, 19, ink, 550)
	return activated
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
	label("Click either button to close and restore focus.", 17, muted)
	ui.close_rect()
	for i in 0..<2 {
		ui.open_rect(.Left, 190, key = i)
		modal_ids[i] = ui.current_identity()
		ui.focusable()
		if button("Continue" if i == 0 else "Cancel") { show_modal = false }
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
	if time == 0.07 || time == 1 || time == 1.001 { assert(!show_modal) }
	if time == 1.005 { assert(show_modal) }
	if time == 1.01 { assert(ui.direct_focus() == modal_ids[0]) }
	if time == 1.02 { assert(ui.direct_focus() == modal_ids[1]) }
	if time == 1.04 { assert(show_modal && list_offset.y == 64 && ui.direct_focus() == modal_ids[0]) }
	if time == 2.005 || time == 2.14 { assert(!show_modal) }
	if time == 2.01 || time == 2.16 { assert(ui.direct_focus() == opener_id && !show_modal) }
	if time == 2.12 { assert(show_modal && ui.direct_focus() == modal_ids[0]) }
}
