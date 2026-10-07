package ui

import "core:testing"
import "core:mem"

@(private) Virtual_Test_Key :: distinct u64
@(private) virtual_probe: Virtual_List
@(private) virtual_probe_focus: int
@(private) virtual_probe_scroll: f32 = -1
@(private) virtual_probe_key: Virtual_Test_Key
@(private) virtual_probe_id: Identity
@(private) virtual_probe_payload: ^int

@(private)
virtual_list_pipeline :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	keys := make([]Virtual_Test_Key, 20001)
	for i in 0..<20000 { keys[i] = Virtual_Test_Key(i + 1) }
	virtual_list_set_items(&virtual_probe, keys[:20000])
	virtual_probe_focus = 2
	frame := Frame_State{update = virtual_probe_scene}
	frame.frame.input = {mouse_inside = true, mouse_position = {40, 40}}
	build_frame(nil, 0, {200, 100}, &frame)
	id, payload := virtual_probe_id, virtual_probe_payload
	payload^ = 77
	virtual_probe_focus = -1
	build_frame(nil, 1, {200, 100}, &frame)
	frame.frame.input.scroll_delta = {0, 200000}
	build_frame(nil, 2, {200, 100}, &frame)
	testing.expect(t, virtual_probe.first > 9000)
	testing.expect_value(t, virtual_probe_id, id)
	testing.expect_value(t, virtual_probe_payload, payload)
	testing.expect_value(t, payload^, 77)
	// Insert and reverse: key 3 retains identity/state even far offscreen.
	keys[0] = 20001
	for i in 1..<20001 { keys[i] = Virtual_Test_Key(20001 - i) }
	virtual_list_set_items(&virtual_probe, keys)
	frame.frame.input = {}
	build_frame(nil, 3, {200, 100}, &frame)
	testing.expect_value(t, virtual_probe_id, id)
	testing.expect_value(t, virtual_probe_payload, payload)
	testing.expect_value(t, virtual_probe_key, Virtual_Test_Key(3))
	frame.frame.input.keys_pressed = {.Tab}
	build_frame(nil, 4, {200, 100}, &frame)
	testing.expect_value(t, virtual_probe_key, Virtual_Test_Key(2))
	testing.expect(t, virtual_probe.first <= 19999 && virtual_probe.end > 19999) // Keyboard navigation reveals it.
	// Remove the focused key: no unrelated replacement inherits its focus.
	keys[19999] = keys[20000]
	virtual_list_set_items(&virtual_probe, keys[:20000])
	frame.frame.input = {}
	build_frame(nil, 5, {200, 100}, &frame)
	testing.expect_value(t, frame.interaction.focused, Identity{})
	build_frame(nil, 6, {200, 100}, &frame)
	allocations := tracking.total_allocation_count
	for _ in 0..<20 { build_frame(nil, 7, {200, 100}, &frame) }
	testing.expect_value(t, tracking.total_allocation_count, allocations)
	virtual_probe_scroll = 2000
	build_frame(nil, 8, {200, 100}, &frame)
	testing.expect_value(t, virtual_probe.first, 100)
	virtual_probe_scroll = -1
	virtual_list_set_items(&virtual_probe, keys[:0])
	build_frame(nil, 8, {200, 100}, &frame)
	testing.expect_value(t, len(virtual_probe.rows), 0)
	virtual_list_set_items(&virtual_probe, keys[:10])
	build_frame(nil, 9, {200, 0}, &frame)
	testing.expect_value(t, virtual_probe.first, virtual_probe.end)
	destroy_frame_state(&frame)
	destroy_virtual_list(&virtual_probe)
	delete(keys)
	testing.expect_value(t, len(tracking.allocation_map), 0)
}

@(private)
virtual_probe_scene :: proc() {
	open_virtual_list(&virtual_probe, 20, reveal = virtual_probe_focus)
	if virtual_probe_scroll >= 0 { scroll_to({0, virtual_probe_scroll}) }
	for index in virtual_list_rows(&virtual_probe) {
		visible := open_virtual_row(&virtual_probe, index, focusable = false)
		// A focused editor/control descendant must keep the row alive too.
		open_rect_at(current_rect(), key = 1)
		focusable()
		value := state(int)
		if index == virtual_probe_focus { request_focus() }
		if focused() {
			virtual_probe_id, virtual_probe_payload = current_identity(), value
			virtual_probe_key = Virtual_Test_Key(virtual_probe.keys[index].integer)
		}
		if visible { paint(color = {1, 0, 0, 1}) }
		close_rect()
		close_rect()
	}
	assert(len(virtual_probe.rows) <= virtual_probe.end - virtual_probe.first + 5)
	assert(len(virtual_probe.rows) <= 10)
	close_virtual_list(&virtual_probe)
}
