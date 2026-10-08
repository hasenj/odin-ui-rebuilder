package ui

import "core:testing"
import "core:mem"
import "core:strings"
import "core:path/filepath"

@(private) binding_string, binding_moved: string
@(private) binding_bytes: [dynamic]u8
@(private) binding_stage: int
@(private) binding_ids: [2]Identity
@(private) binding_results: [2]Text_Edit_Result
@(private) binding_ui_alloc, binding_model_alloc: ^mem.Tracking_Allocator
@(private) binding_warm_ui, binding_warm_model: i64

@(private)
bound_editor_pipeline :: proc(t: ^testing.T) {
	ui_alloc, model_alloc: mem.Tracking_Allocator
	mem.tracking_allocator_init(&ui_alloc, context.allocator)
	mem.tracking_allocator_init(&model_alloc, context.allocator)
	defer mem.tracking_allocator_destroy(&ui_alloc)
	defer mem.tracking_allocator_destroy(&model_alloc)
	context.allocator = mem.tracking_allocator(&ui_alloc)
	binding_ui_alloc, binding_model_alloc = &ui_alloc, &model_alloc
	model := mem.tracking_allocator(&model_alloc)
	binding_string = strings.clone("seed", model)
	binding_bytes = {} // No caller initialization; adopts the active allocator on first edit.
	binding_stage, binding_ids = 0, {}
	frames: [40]Capture_Frame
	for &frame, i in frames { frame = {size = {300, 100}, scale = 1, time = f64(i) / 60} }
	result := capture_frames(binding_scene, frames[:])
	testing.expect_value(t, result.error, Capture_Error.None)
	// Both UI identities and the window are gone, but model values remain valid.
	testing.expect_value(t, binding_moved, "new")
	testing.expect_value(t, string(binding_bytes[:]), "other")
	testing.expect_value(t, binding_bytes.allocator, model)
	delete(binding_string, model); delete(binding_moved, model); delete(binding_bytes)
	binding_string, binding_moved, binding_bytes = "", "", {}
	testing.expect_value(t, len(ui_alloc.allocation_map), 0)
	testing.expect_value(t, len(model_alloc.allocation_map), 0)
}

@(private)
binding_scene :: proc() {
	stage := binding_stage
	defer { binding_stage += 1 }
	if _, ok := find_font("Bound"); !ok {
		path, _ := filepath.join({filepath.dir(#location().file_path), "../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
		defer delete(path)
		_, err := load_font(path, "Bound"); assert(err == .None)
	}
	model := mem.tracking_allocator(binding_model_alloc)
	ops: [2]Text_Operation
	n := 0
	target := 0 if stage < 17 else 1
	if stage > 0 && stage != 11 && stage != 12 { request_focus(binding_ids[target]) }
	if stage == 6 { delete(binding_string, model); binding_string = strings.clone("reset", model) }
	if stage == 14 { binding_moved, binding_string = binding_string, "" }
	if stage == 21 { resize(&binding_bytes, 5); copy(binding_bytes[:], "other") }
	switch stage {
	case 1: ops[0] = {kind = .Commit, text = "X"}; n = 1
	case 2, 8, 10, 17, 18:
		ops[0] = {kind = .Command, command = .Select_All}
		ops[1] = {kind = .Mark, text = "preedit", selection = {7, 7}}
		if stage == 10 { ops[1] = {kind = .Commit, text = "new"} }
		if stage == 17 { ops[1] = {kind = .Commit, text = "byte"} }
		n = 2
	case 4: ops[0] = {kind = .Commit, text = "done"}; n = 1
	case 5, 7, 13, 15, 22: ops[0] = {kind = .Command, command = .Undo}; n = 1
	case 6, 21: ops[0] = {kind = .Commit, text = "stale"}; n = 1
	case 9: ops[0] = {kind = .Cancel_Composition}; n = 1
	case 14: ops[0] = {kind = .Commit, text = "!"}; n = 1
	case 20: ops[0] = {kind = .Commit, text = "after"}; n = 1
	case 23: ops[0] = {kind = .Commit, text = "disabled"}; n = 1
	case 24: ops[0] = {kind = .Command, command = .Submit}; n = 1
	}
	current_frame().input.text = {target = text_target(binding_ids[target]), operations = ops[:n]}
	for position in 0..<2 {
		i := 1-position if stage >= 16 else position
		if stage == 11 && i == 0 { continue }
		open_rect_at({{0, f32(i)*50}, {300, 45}}, key = i)
		binding_ids[i] = current_identity()
		// Internal editor storage must not occupy the caller's typed state slot.
		state(int)^ += 1
		if i == 0 {
			value := &binding_moved if stage >= 14 else &binding_string
			binding_results[i] = edit_text(value, "Bound", allocator = model)
		} else {
			// Changing the active allocator is supported too; editor memory still
			// belongs to the window and the array keeps its own allocator.
			context.allocator = model if stage != 18 else context.allocator
			binding_results[i] = edit_text(&binding_bytes, "Bound", clear = stage == 19, enabled = stage != 23)
		}
		assert(binding_results[i].error == .None)
		close_rect()
	}
	value := binding_moved if stage >= 14 else binding_string
	switch stage {
	case 1: assert(value == "seedX" && binding_results[0].changed)
	case 2, 3: assert(value == "seedX" && binding_results[0].composing && !binding_results[0].changed && !binding_results[0].empty)
	case 4: assert(value == "done" && binding_results[0].changed && !binding_results[0].composing)
	case 5: assert(value == "seedX")
	case 6, 7, 9: assert(value == "reset" && !binding_results[0].changed)
	case 8: assert(value == "reset" && binding_results[0].composing)
	case 10..=13: assert(value == "new")
	case 14: assert(value == "new!")
	case 15: assert(value == "new")
	case 17: assert(string(binding_bytes[:]) == "byte" && binding_results[1].changed)
	case 18: assert(string(binding_bytes[:]) == "byte" && binding_results[1].composing && !binding_results[1].changed)
	case 19: assert(len(binding_bytes) == 0 && binding_results[1].changed && binding_results[1].empty && !binding_results[1].composing)
	case 20: assert(string(binding_bytes[:]) == "after")
	case 21..=23: assert(string(binding_bytes[:]) == "other" && !binding_results[1].changed)
	case 24: assert(binding_results[1].submitted && !binding_results[1].changed)
	}
	if stage == 27 { binding_warm_ui = binding_ui_alloc.total_allocation_count; binding_warm_model = binding_model_alloc.total_allocation_count }
	if stage > 27 {
		assert(binding_ui_alloc.total_allocation_count == binding_warm_ui)
		assert(binding_model_alloc.total_allocation_count == binding_warm_model)
	}
}
