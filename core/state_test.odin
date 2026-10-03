package ui

import "core:testing"
import "core:mem"

@(private) State_Probe :: struct {value: int, owned: [dynamic]int}
@(private) state_probe_order: [2]int
@(private) state_probe_pointers: [2]^State_Probe
@(private) state_probe_grow: bool
@(private) state_probe_created, state_probe_destroyed: int

@(private)
retained_state_pipeline :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	first := Frame_State{update = state_probe_scene}
	second := Frame_State{update = state_probe_scene}
	state_probe_order = {1, 2}
	state_probe_grow = false
	state_probe_created, state_probe_destroyed = 0, 0
	build_frame(nil, 0, {100, 100}, &first)
	original := state_probe_pointers
	original[0].value, original[1].value = 10, 20
	// Different declaration order and slot-array growth cannot move payloads.
	state_probe_order = {2, 1}
	state_probe_grow = true
	build_frame(nil, 1, {100, 100}, &first)
	testing.expect_value(t, state_probe_pointers, original)
	testing.expect_value(t, original[0].value, 10)
	testing.expect_value(t, original[1].value, 20)
	state_probe_grow = false
	build_frame(nil, 2, {100, 100}, &first)
	testing.expect_value(t, state_probe_destroyed, 1000)
	allocations := tracking.total_allocation_count
	for _ in 0..<20 { build_frame(nil, 3, {100, 100}, &first) }
	testing.expect_value(t, tracking.total_allocation_count, allocations)
	build_frame(nil, 0, {100, 100}, &second)
	testing.expect(t, state_probe_pointers[0] != original[0])
	testing.expect_value(t, state_probe_pointers[0].value, 0)
	destroy_frame_state(&second)
	state_probe_order = {1, 0}
	build_frame(nil, 4, {100, 100}, &first)
	testing.expect_value(t, state_probe_destroyed, 1003)
	state_probe_order = {1, 2}
	build_frame(nil, 5, {100, 100}, &first)
	testing.expect_value(t, state_probe_pointers[0], original[0])
	testing.expect_value(t, state_probe_pointers[1].value, 0)
	destroy_frame_state(&first)
	testing.expect_value(t, state_probe_created, state_probe_destroyed)
	testing.expect_value(t, len(tracking.allocation_map), 0)
}

@(private) state_probe_scene :: proc() {
	if state_probe_grow {
		for i in 10..<1010 {
			open_identity(key = i)
			state(State_Probe, state_probe_init, state_probe_cleanup)
			close_identity()
		}
	}
	for key in state_probe_order {
		if key == 0 { continue }
		open_identity(key = key)
		value := state(State_Probe, state_probe_init, state_probe_cleanup)
		assert(value == state(State_Probe))
		state_probe_pointers[key - 1] = value
		close_identity()
	}
}
@(private) state_probe_init :: proc(value: ^State_Probe) { append(&value.owned, 123); state_probe_created += 1 }
@(private) state_probe_cleanup :: proc(value: ^State_Probe) { assert(value.owned[0] == 123); delete(value.owned); state_probe_destroyed += 1 }
