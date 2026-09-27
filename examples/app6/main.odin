package app6

import ui "../../core"

body, labels: ui.Font
loaded: bool
ink :: ui.Color{0.91, 0.93, 0.97, 1}
gold :: ui.Color{0.96, 0.79, 0.51, 1}
muted :: ui.Color{0.57, 0.64, 0.74, 1}

main :: proc() {
	ui.open_window("Odin UI Rebuilder — Arabic & bidi", 980, 850, update, frame_timing = .Summary)
}

update :: proc() {
	if !loaded {
		err: ui.Text_Error
		body, err = ui.load_font("examples/app6/assets/Amiri-Regular.ttf", name = "body")
		assert(err == .None, "Run app6 from the repository root; could not load Amiri")
		labels, err = ui.load_font("examples/app5/assets/NotoSansDisplay-VariableFont.ttf", name = "labels")
		assert(err == .None)
		loaded = true
	}
	ui.paint(color = {0.055, 0.07, 0.10, 1})
	ui.pad(28)
	label("TEXT / 02", 13)
	label("Arabic & mixed-direction text", 32, ink)
	label("One font for Arabic and Latin. Reading direction is independent of alignment.", 15)
	ui.pad4(14, 0, 0, 0)

	panel_open(124)
	{
		label("ARABIC / JOINING & DIACRITICS / RIGHT ALIGNED", 12)
		line("السَّلَامُ عَلَيْكُمْ — أَهْلًا وَسَهْلًا", 36, color = gold, right = true)
	}
	panel_close()

	panel_open(170)
	{
		label("MIXED ARABIC & ENGLISH / AUTOMATIC DIRECTION", 12)
		line("مرحباً بكم في Odin — الإصدار 6", 30, right = true)
		line("Hello, مرحباً بالعالم! Welcome to the UI.", 30)
	}
	panel_close()

	panel_open(158)
	{
		label("NUMBERS, PARENTHESES & PUNCTUATION", 12)
		line("الطلب (ABC-123): العدد 42، السعر ١٢٣٫٤٥", 28, right = true)
		line("تجربة [Odin 2026] — العربية (جميلة)", 28, color = gold, right = true)
	}
	panel_close()

	panel_open(165)
	{
		label("SAME STRING / FORCED LTR THEN RTL / BOTH LEFT ALIGNED", 12)
		line("Hello (مرحبا) 123!", 28, direction = .LTR)
		line("Hello (مرحبا) 123!", 28, direction = .RTL, color = gold)
	}
	panel_close()
}

panel_open :: proc(height: f32) {
	ui.open_rect(.Top, height)
	ui.paint(color = {0.10, 0.13, 0.18, 1}, corners = 12)
	ui.pad2(12, 20)
}

panel_close :: proc() {
	ui.close_rect()
	ui.pad4(12, 0, 0, 0)
}

label :: proc(value: string, size: f32, color: ui.Color = muted) {
	m, err := ui.measure_text(value, labels, size)
	assert(err == .None)
	ui.open_rect(.Top, m.height + 5)
	{
		_, err = ui.text(value, labels, size, color)
		assert(err == .None)
	}
	ui.close_rect()
}

line :: proc(value: string, size: f32, direction: ui.Text_Direction = .Auto, color: ui.Color = ink, right: bool = false) {
	m, err := ui.measure_text(value, body, size, direction = direction)
	assert(err == .None)
	ui.open_rect(.Top, m.height + 4)
	{
		if right { ui.open_rect(.Right, m.width) }
		_, err = ui.text(value, "body", size, color, direction = direction)
		assert(err == .None)
		if right { ui.close_rect() }
	}
	ui.close_rect()
}
