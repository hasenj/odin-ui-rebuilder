package app5

import ui "../../core"
import "core:fmt"

sans, serif: ui.Font
loaded: bool
ink :: ui.Color{0.91, 0.93, 0.97, 1}
muted :: ui.Color{0.57, 0.64, 0.74, 1}

main :: proc() {
	ui.open_window("Odin UI Rebuilder — Latin text", 980, 800, update, frame_timing = .Summary)
}

update :: proc() {
	if !loaded {
		err: ui.Text_Error
		sans, err = ui.load_font("examples/app5/assets/NotoSansDisplay-VariableFont.ttf", name = "sans")
		assert(err == .None, "Run app5 from the repository root; could not load Noto Sans Display")
		serif, err = ui.load_font("examples/app5/assets/NotoSerifDisplay-VariableFont.ttf", name = "serif")
		assert(err == .None, "Could not load Noto Serif Display")
		loaded = true
	}
	ui.paint(color = {0.055, 0.07, 0.10, 1})
	ui.pad(28)
	line("TEXT / 01", "sans", 13, muted, 600)
	line("A little type goes a long way.", sans, 36, ink, 600)
	line("HarfBuzz shaping · FreeType outlines · GPU glyph atlas", sans, 16, muted)
	ui.pad4(16, 0, 0, 0)

	ui.open_rect(.Top, 174)
	{
		ui.paint(color = {0.10, 0.13, 0.18, 1}, corners = 12)
		ui.pad2(16, 20)
		line("SANS & SERIF", "sans", 12, muted, 700)
		line("The quick brown fox jumps over the lazy dog.", "sans", 23, ink)
		line("The quick brown fox jumps over the lazy dog.", serif, 23, {0.94, 0.77, 0.52, 1})
		line("Café, crème brûlée, São Paulo — naïve façade. 0123456789", sans, 17, muted)
	}
	ui.close_rect()
	ui.pad4(16, 0, 0, 0)

	ui.open_rect(.Top, 184)
	{
		ui.paint(color = {0.10, 0.13, 0.18, 1}, corners = 12)
		ui.pad2(14, 20)
		line("ONE VARIABLE FONT / FOUR WEIGHTS", sans, 12, muted, 700)
		weights := [?]f32{300, 400, 700, 900}
		labels := [?]string{"300   Light — almost weightless", "400   Regular — everyday reading", "700   Bold — a stronger voice", "900   Black — impossible to miss"}
		for weight, i in weights {
			line(labels[i], sans, 21, ink, weight, gap = 0)
		}
	}
	ui.close_rect()
	ui.pad4(18, 0, 0, 0)
	line("12 px   Small text still deserves good spacing.", sans, 12, ink)
	line("16 px   AVATAR · office · affinity · café · cafe\u0301", sans, 16, ink)
	line("24 px   Typography is part of the interface.", sans, 24, ink)
	ui.pad4(12, 0, 0, 0)

	// Measured text sets a button's dimensions. Painting and text emission do
	// not change layout; the caller controls exactly how space gets consumed.
	metrics, err := ui.measure_text("Measured button", font = "sans", size = 16, weight = 600)
	assert(err == .None)
	ui.open_rect(.Top, metrics.height + 20)
	{
		ui.open_rect(.Left, metrics.width + 32)
		{
			ui.paint(color = {0.22, 0.42, 0.68, 1}, corners = 8)
			ui.pad2(10, 16)
			_, err = ui.text("Measured button", font = "sans", size = 16, weight = 600)
			assert(err == .None)
		}
		ui.close_rect()
		ui.pad4(10, 0, 0, 20)
		frame := ui.current_frame()
		// Text changes each second, exercising new glyph uploads after warm-up.
		buffer: [100]u8
		status := fmt.bprintf(buffer[:], "Scale: %.0fx  /  Running: %d s", frame.scale, int(frame.time))
		_, err = ui.text(status, font = sans, size = 14, color = muted)
		assert(err == .None)
	}
	ui.close_rect()
}

// Explicitly cut a line-height region, then emit text into it. This helper is
// application code; ui.text itself neither consumes space nor creates a layout node.
line :: proc(value: string, font: ui.Font_Ref, size: f32, color: ui.Color, weight: f32 = 0, gap: f32 = 5) {
	metrics, err := ui.measure_text(value, font, size, weight)
	assert(err == .None)
	ui.open_rect(.Top, metrics.height + gap)
	{
		_, err = ui.text(value, font, size, color, weight)
		assert(err == .None)
	}
	ui.close_rect()
}
