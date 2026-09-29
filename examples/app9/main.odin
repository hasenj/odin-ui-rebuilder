package app9

import ui "../../core"
import "core:math"

font: ui.Font

main :: proc() {
	ui.open_window("Odin UI Rebuilder — Transparent window", 780, 510, update,
		frame_timing = .Summary, decorated = ODIN_OS != .Darwin, transparent = true)
}

update :: proc() {
	if font == 0 {
		err: ui.Text_Error
		font, err = ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf")
		assert(err == .None, "Run app9 from the repository root")
	}
	// Deliberately leave the root, padding and gaps unpainted.
	ui.pad(36)
	ui.open_rect(.Top, 132)
	{
		ui.paint(color = {0.07, 0.10, 0.16, 1}, corners = 28)
		ui.pad(24)
		line("A window without the frame.", 28, 600)
		line("Opaque paint. Transparent space. Your shapes.", 16)
	}
	ui.close_rect()
	ui.pad4(28, 0, 0, 0)
	ui.open_rect(.Bottom, 46)
	{
		ui.paint(color = {0.07, 0.10, 0.16, 0.9}, corners = 18)
		ui.pad2(8, 20)
		when ODIN_OS == .Darwin {
			line("Drag a painted area to move  /  Command-Q to quit", 14)
		} else {
			line("Use your window manager shortcuts to move / close", 14)
		}
	}
	ui.close_rect()
	ui.pad4(0, 0, 28, 0)
	ui.open_rect(.Left, 170)
	{
		ui.paint(color = {0.17, 0.47, 0.87, 0.55}, corners = 26)
		ui.pad(20)
		line("55%", 32, 600)
		line("Translucent", 16)
	}
	ui.close_rect()
	ui.pad4(0, 0, 0, 28)
	// A moving circle reveals the desktop again where it was last frame.
	area := ui.current_rect()
	diameter := min(130, min(area.size.x, area.size.y))
	x := area.position.x + max(area.size.x - diameter, 0) *
		(0.5 + 0.5 * math.sin(f32(ui.current_frame().time) * 1.2))
	append(&ui.current_frame().surfaces, ui.Surface{
		position = {x, area.position.y + max(area.size.y - diameter, 0) * 0.5},
		size = {diameter, diameter}, background = {0.96, 0.57, 0.25, 0.85},
		corner_radius = diameter * 0.5,
	})
}

line :: proc(value: string, size: f32, weight: f32 = 0) {
	ui.open_rect(.Top, size * 1.5)
	{
		area := ui.current_rect()
		if area.size.x > 0 && area.size.y > 0 {
			text, err := ui.layout_text_fit(value, font, max_width = area.size.x,
				max_height = area.size.y, size = size, weight = weight)
			assert(err == .None)
			assert(ui.draw_text_layout(text, {0.94, 0.96, 1, 1}) == .None)
		}
	}
	ui.close_rect()
}
