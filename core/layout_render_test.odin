package ui

import "core:testing"
import "core:fmt"
import "core:path/filepath"

@(private) layout_text_test_stage: int
@(private) layout_text_test_heights: [3]f32
@(private) layout_text_test_font: Font

@(private)
local_layout_text_pipeline :: proc(t: ^testing.T) {
	layout_text_test_stage = 0
	layout_text_test_font = 0
	frames := [?]Capture_Frame{
		{size = {360, 600}, scale = 1},
		{size = {180, 600}, scale = 2},
		{size = {360, 600}, scale = 1},
	}
	result := capture_frames(local_layout_text_scene, frames[:])
	testing.expect_value(t, result.error, Capture_Error.None)
	testing.expect_value(t, layout_text_test_stage, 3)
	testing.expect(t, layout_text_test_heights[1] > layout_text_test_heights[0])
	testing.expect_value(t, layout_text_test_heights[0], layout_text_test_heights[2])
}

@(private)
local_layout_text_scene :: proc() {
	if layout_text_test_font == 0 {
		path, _ := filepath.join({filepath.dir(#location().file_path), "../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
		defer delete(path)
		err: Text_Error
		layout_text_test_font, err = load_font(path)
		assert(err == .None)
	}
	font := layout_text_test_font
	// Rect cutting allocates the icon area. A local content-sized column
	// measures wrapped text within the remaining width, without fill behavior.
	open_rect(.Left, 40)
	close_rect()
	open_layout(.Top, {padding = {6, 10}})
	paint()
	open_box({gap = 5})
	paragraph := "A paragraph that wraps when its allocated width becomes smaller.\nAn explicit second line."
	text_item(paragraph, font, 16)
	for i in 0..<2 {
		buffer: [32]u8
		// These fit at both widths: intrinsic reuse must preserve hard breaks.
		text_item(fmt.bprintf(buffer[:], "Label %d\nSecond line", i + 1), font, 16)
		for &byte in buffer { byte = 'X' }
	}
	close_box()
	bounds, err := close_layout()
	assert(err == .None)
	width := current_frame().size.x - 20 - 32 - 8
	expected, text_err := layout_text(paragraph, font, width, 16)
	assert(text_err == .None)
	label, _ := layout_text("Label 1\nSecond line", font, width, 16)
	assert(abs(bounds.size.y - (12 + expected.height + 2 * label.height + 10)) < 0.001)
	assert(current_rect().position.y == bounds.size.y)
	// Independent text-layout results agree with final leaf geometry. Copied
	// commands still contain the labels, despite overwriting the caller buffer.
	store := &active_state.layout
	assert(abs(store.measure[2].size.y - expected.height) < 0.001)
	for command, i in store.commands {
		if command.kind != .Text || i < 2 { continue }
		value := transmute(string)store.strings[command.value_start:command.value_end]
		assert(value == "Label 1\nSecond line" || value == "Label 2\nSecond line")
		assert(store.measure[command.node].text.line_count == 2)
	}
	layout_text_test_heights[layout_text_test_stage] = bounds.size.y
	layout_text_test_stage += 1
	// Error propagation still closes the scope and restores ordinary cutting.
	open_layout(.Top)
	text_item("missing font", Font(0))
	_, missing := close_layout()
	assert(missing != .None)
	assert(current_rect().size.y >= 0)
}
