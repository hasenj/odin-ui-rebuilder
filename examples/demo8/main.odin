package demo8

import ui "../../core"

sans: ui.Font
ink :: ui.Color{0.91, 0.94, 0.98, 1}
muted :: ui.Color{0.55, 0.63, 0.74, 1}

main :: proc() {
	ui.open_window("Odin UI Rebuilder — Animated hover", 960, 640, update, frame_timing = .Summary)
}

update :: proc() {
	if sans == 0 {
		err: ui.Text_Error
		sans, err = ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf")
		assert(err == .None, "Run demo8 from the repository root")
	}
	ui.paint(color = {0.055, 0.07, 0.10, 1})
	ui.open_rect(.Top, 64)
	{
		ui.paint(color = {0.10, 0.13, 0.18, 1})
		ui.pad2(12, 24)
		caption("Workspace", 22, ink, .Start, 600)
	}
	ui.close_rect()
	ui.open_rect(.Bottom, 36)
	{
		ui.paint(color = {0.10, 0.13, 0.18, 1})
		ui.pad2(6, 24)
		caption("Ready  /  Move the pointer over a sidebar button", 13, muted)
	}
	ui.close_rect()
	ui.open_rect(.Left, 112)
	{
		ui.paint(color = {0.075, 0.095, 0.135, 1})
		ui.pad(16)
		mode_button("Files", {0.19, 0.39, 0.68, 1})
		ui.pad4(16, 0, 0, 0)
		mode_button("Search", {0.12, 0.43, 0.40, 1})
		ui.pad4(16, 0, 0, 0)
		mode_button("Tools", {0.40, 0.29, 0.62, 1})
	}
	ui.close_rect()
	ui.pad(32)
	ui.open_rect(.Top, 48)
	{
		caption("Room to work.", 30, ink, .Start, 600)
	}
	ui.close_rect()
	ui.open_rect(.Top, 32)
	{
		caption("Three modes. Just hover for now.", 17, muted)
	}
	ui.close_rect()
}

mode_button :: proc(label: string, hover_color: ui.Color, loc := #caller_location) {
	ui.open_rect(.Top, 80, loc = loc)
	{
		target: f32 = 0
		if ui.hovered() { target = 1 }
		amount := ui.animate_f32(target, half_life = 0.06)
		normal := ui.Color{0.13, 0.17, 0.23, 1}
		color := normal + (hover_color - normal) * amount
		ui.paint(color = color, corners = 12)
		ui.pad(8)
		caption(label, 17, ink, .Center, 600)
	}
	ui.close_rect()
}

caption :: proc(value: string, size: f32, color: ui.Color, align: ui.Text_Align = .Start, weight: f32 = 0) {
	area := ui.current_rect()
	if area.size.x <= 0 || area.size.y <= 0 { return }
	text, err := ui.layout_text_fit(value, sans, max_width = area.size.x,
		max_height = area.size.y, size = size, weight = weight)
	assert(err == .None)
	assert(ui.draw_text_layout(text, color, align = align, valign = .Center) == .None)
}
