package app7

import ui "../../core"

sans, arabic: ui.Font
loaded: bool
ink :: ui.Color{0.91, 0.93, 0.97, 1}
gold :: ui.Color{0.96, 0.79, 0.51, 1}
muted :: ui.Color{0.57, 0.64, 0.74, 1}

main :: proc() {
	ui.open_window("Odin UI Rebuilder — Wrap & fit", 920, 880, update, frame_timing = .Summary)
}

update :: proc() {
	if !loaded {
		err: ui.Text_Error
		sans, err = ui.load_font("examples/app5/assets/NotoSansDisplay-VariableFont.ttf", name = "sans")
		assert(err == .None, "Run app7 from the repository root")
		arabic, err = ui.load_font("examples/app6/assets/Amiri-Regular.ttf", name = "arabic")
		assert(err == .None)
		loaded = true
	}
	ui.paint(color = {0.055, 0.07, 0.10, 1})
	ui.pad(28)
	label("TEXT / 03", 13)
	label("A little room. The right words.", 30, ink)
	label("Resize the window: paragraphs wrap; button labels shrink, then wrap at 12 px.", 15)
	ui.pad4(18, 0, 0, 0)

	label("FIXED BUTTONS / 24 PX DESIRED / 12 PX MINIMUM", 12)
	ui.open_rect(.Top, 64)
	{
		available := max(ui.current_rect().size.x - 24, 0)
		button(available * 0.45, "Save all changes")
		ui.pad4(0, 0, 0, 12)
		button(available * 0.33, "Save all changes")
		ui.pad4(0, 0, 0, 12)
		button(available * 0.22, "Save all changes")
	}
	ui.close_rect()
	ui.pad4(10, 0, 0, 0)
	label("Blue: fits. Amber: width or height still overflows at 12 px. Clipping comes later.", 13)
	ui.pad4(18, 0, 0, 0)

	paragraph("WORD WRAPPING / HEIGHT COMES FROM THE TEXT",
		"A paragraph starts with an available width. The text chooses its line breaks, and the resulting height tells us how much space to cut. Measurement and painting share the same prepared layout.\n\nAn explicit blank line is preserved, too.",
		sans, 20, .Start, ink)
	ui.pad4(18, 0, 0, 0)
	paragraph("ARABIC & LATIN / BIDI RESOLVED FOR EACH LINE",
		"مرحباً بكم في عالم الواجهات. هذه فقرة عربية تحتوي على كلمات English وأرقام 123، ويتغيّر عدد السطور عندما نغيّر عرض النافذة. السَّلَامُ عَلَيْكُمْ — أَهْلًا وَسَهْلًا بكم!",
		arabic, 29, .End, gold)
}

button :: proc(width: f32, value: string) {
	ui.open_rect(.Left, width)
	{
		// Use the actual cut bounds: available height may shrink with the window.
		bounds := ui.current_rect()
		text, err := ui.layout_text_fit(value, sans, max_width = max(bounds.size.x - 24, 0),
			max_height = max(bounds.size.y - 12, 0), size = 24, weight = 600, wrap_at_min = true)
		assert(err == .None)
		color := ui.Color{0.19, 0.39, 0.68, 1}
		if text.overflow { color = {0.48, 0.29, 0.10, 1} }
		ui.paint(color = color, corners = 9)
		ui.pad2(6, 12)
		err = ui.draw_text_layout(text, ink, align = .Center, valign = .Center)
		assert(err == .None)
	}
	ui.close_rect()
}

paragraph :: proc(title, value: string, font: ui.Font, size: f32, align: ui.Text_Align, color: ui.Color) {
	width := max(ui.current_rect().size.x - 40, 0)
	text, err := ui.layout_text(value, font, max_width = width, size = size)
	assert(err == .None)
	heading, heading_error := ui.layout_text(title, sans, max_width = width, size = 12)
	assert(heading_error == .None)
	ui.open_rect(.Top, text.height + heading.height + 43)
	{
		ui.paint(color = {0.10, 0.13, 0.18, 1}, corners = 12)
		ui.pad2(16, 20)
		label(title, 12)
		ui.pad4(6, 0, 0, 0)
		err = ui.draw_text_layout(text, color, align = align)
		assert(err == .None)
	}
	ui.close_rect()
}

label :: proc(value: string, size: f32, color: ui.Color = muted) {
	text, err := ui.layout_text(value, sans, max_width = ui.current_rect().size.x, size = size)
	assert(err == .None)
	ui.open_rect(.Top, text.height + 5)
	{
		err = ui.draw_text_layout(text, color)
		assert(err == .None)
	}
	ui.close_rect()
}
