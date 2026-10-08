package ui

import "core:testing"
import "core:path/filepath"
import "core:mem"

@(private) editor_test_stage: int
@(private) editor_test_allocations: i64
@(private) editor_test_tracking: ^mem.Tracking_Allocator
@(private)
editor_frame_pipeline :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	editor_test_tracking = &tracking
	editor_test_stage = 0
	frames: [30]Capture_Frame
	for &frame in frames { frame = {size = {300, 80}, scale = 2, time = 0.1} }
	result := capture_frames(editor_test_scene, frames[:])
	testing.expect_value(t, result.error, Capture_Error.None)
	testing.expect_value(t, editor_test_stage, len(frames))
	testing.expect_value(t, len(tracking.allocation_map), 0)
	editor_test_tracking = nil
}
@(private) editor_test_scene :: proc() {
	defer { editor_test_stage += 1 }
	if _, found := find_font("EditorTest"); !found {
		path, _ := filepath.join({filepath.dir(#location().file_path), "../examples/assets/fonts/Amiri-Regular.ttf"})
		defer delete(path)
		_, err := load_font(path, "EditorTest"); assert(err == .None)
	}
	editor := state(Text_Edit, proc(e: ^Text_Edit) { init_text_edit(e, "abc سلام 123") }, destroy_text_edit)
	request_focus()
	result := edit_text_state(editor, "EditorTest", 24)
	assert(result.error == .None)
	if editor_test_stage == 2 {
		// Follow visual arrow positions across mixed-direction runs, and then
		// collapse a logical selection to its left/right visual extremities.
		index, x := hit_caret(editor, -100)
		editor.buffer.cursor, editor.buffer.anchor = index, index
		editor.caret_byte, editor.caret_x = index, x
		for _ in 0..<100 {
			before := editor.caret_x
			move_visual(editor, true, false)
			assert(editor.caret_x >= before)
			if editor.caret_x == before { break }
		}
		assert(abs(editor.caret_x - editor.metrics.width) < 0.001)
		editor.buffer.anchor, editor.buffer.cursor = 0, len(editor.buffer.bytes)
		move_visual(editor, false, false)
		assert(editor.caret_x == 0 && editor.buffer.anchor == editor.buffer.cursor)
	}
	if editor_test_stage == 5 { editor_test_allocations = editor_test_tracking.total_allocation_count }
	if editor_test_stage > 5 { assert(editor_test_tracking.total_allocation_count == editor_test_allocations, "Warm editor frames must reuse allocations") }
}
