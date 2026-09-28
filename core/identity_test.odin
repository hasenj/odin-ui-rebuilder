package ui

import "core:testing"
import "core:mem"
import "core:math"

// Called by the sequential frame test: the UI has one implicit active frame.
@(private)
identity_animation_pipeline :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	state := Frame_State{update = identity_scene}
	identity_probe = Identity_Probe{repeat_count = 2}
	defer { identity_probe = {} }
	build_frame(nil, 0, {200, 100}, &state)
	initial := identity_probe.ids
	testing.expect_value(t, identity_probe.amount, f32(0))
	for a, i in initial {
		testing.expect(t, a.index != 0)
		for b in initial[i + 1:] { testing.expect(t, a != b) }
	}
	root := state.identities.stack[0].id
	testing.expect(t, state.identities.nodes[initial[9].index - 1].path.group.key !=
		state.identities.nodes[initial[10].index - 1].path.group.key)
	testing.expect_value(t, state.identities.nodes[initial[12].index - 1].path.group.key,
		state.identities.nodes[initial[13].index - 1].path.group.key)
	testing.expect_value(t, state.identities.nodes[initial[12].index - 1].path.occurrence, u32(0))
	testing.expect_value(t, state.identities.nodes[initial[13].index - 1].path.occurrence, u32(1))
	testing.expect_value(t, state.identities.nodes[initial[0].index - 1].path.group.parent, root)
	testing.expect_value(t, state.identities.nodes[initial[1].index - 1].path.group.parent, initial[0])
	// Reordering a different key leaves every existing identity unchanged.
	identity_probe.reorder = true
	state.frame.input.mouse_inside = true
	build_frame(nil, 1, {120, 70}, &state)
	testing.expect_value(t, identity_probe.ids, initial)
	testing.expect(t, math.abs(identity_probe.amount - 0.5) < 0.00001)
	parent := state.identities.nodes[initial[0].index - 1]
	testing.expect_value(t, parent.first_child, initial[3])
	testing.expect_value(t, state.identities.nodes[initial[3].index - 1].next_sibling, initial[1])
	// No elapsed time means no advancement. Reverse halfway without restarting.
	build_frame(nil, 1, {200, 100}, &state)
	testing.expect(t, math.abs(identity_probe.amount - 0.5) < 0.00001)
	state.frame.input.mouse_inside = false
	build_frame(nil, 1.5, {200, 100}, &state)
	testing.expect(t, math.abs(identity_probe.amount - 0.3535534) < 0.00001)
	// Warm animation frames and reordered nodes allocate nothing in Odin.
	allocations := tracking.total_allocation_count
	for i in 0..<30 {
		identity_probe.reorder = i % 2 == 0
		build_frame(nil, 2 + f64(i) / 60, {200, 100}, &state)
	}
	testing.expect_value(t, tracking.total_allocation_count, allocations)
	// Remove just the second occurrence. The first retains its identity.
	identity_probe.repeat_count = 1
	build_frame(nil, 3, {200, 100}, &state)
	testing.expect_value(t, identity_probe.ids[1], initial[1])
	testing.expect(t, !state.identities.nodes[initial[2].index - 1].alive)
	identity_probe.repeat_count = 2
	build_frame(nil, 4, {200, 100}, &state)
	testing.expect(t, identity_probe.ids[2] != initial[2])
	testing.expect_value(t, identity_probe.ids[1], initial[1])
	// A different parent key gives all descendants new identities.
	before := identity_probe.ids
	identity_probe.parent = 1
	build_frame(nil, 5, {200, 100}, &state)
	for id, i in identity_probe.ids { testing.expect(t, id != before[i]) }
	// Missing a full frame reclaims state, counters and lookup records.
	before = identity_probe.ids
	state.update = nil
	build_frame(nil, 6, {200, 100}, &state)
	testing.expect_value(t, len(state.identities.lookup), 0)
	testing.expect_value(t, len(state.identities.counts), 0)
	testing.expect_value(t, len(state.identities.animations), 0)
	testing.expect_value(t, state.identities.nodes[0].first_child, Identity{})
	identity_probe.invalid = before
	state.update = identity_scene
	state.frame.input.mouse_inside = true
	build_frame(nil, 7, {200, 100}, &state)
	for id, i in identity_probe.ids { testing.expect(t, id != before[i]) }
	testing.expect_value(t, identity_probe.amount, f32(1)) // First appearance is at target.
	identity_probe.invalid = {}
	// A churn workload remains bounded by peak simultaneous nodes, not frames.
	state.update = identity_churn_scene
	for i in 0..<8 {
		identity_probe.parent = i
		build_frame(nil, 8 + f64(i), {200, 100}, &state)
	}
	nodes := len(state.identities.nodes)
	for i in 8..<80 {
		identity_probe.parent = i
		build_frame(nil, 8 + f64(i), {200, 100}, &state)
	}
	testing.expect_value(t, len(state.identities.nodes), nodes)
	testing.expect_value(t, len(state.identities.lookup), 128)
	testing.expect_value(t, len(state.identities.counts), 128)
	testing.expect_value(t, len(state.identities.animations), 64)
	destroy_frame_state(&state)
	testing.expect_value(t, len(tracking.allocation_map), 0)
	animation_cadence(t)
}

@(private)
Probe_Document :: distinct i64
@(private)
Probe_Panel :: distinct i64
@(private)
Probe_Animation :: distinct u32
@(private)
Identity_Probe :: struct {
	ids, invalid: [14]Identity,
	reorder: bool,
	repeat_count, parent: int,
	amount: f32,
}
@(private)
identity_probe: Identity_Probe

@(private)
identity_scene :: proc() {
	for id in identity_probe.invalid { assert(!identity_valid(id)) }
	assert(identity_valid(current_identity()))
	open_rect(.Top, 80, key = Probe_Panel(identity_probe.parent))
	{
		identity_probe.ids[0] = current_identity()
		if identity_probe.reorder { identity_probe.ids[3] = identity_probe_leaf(Probe_Document(8)) }
		for i in 0..<identity_probe.repeat_count {
			identity_probe.ids[1 + i] = open_identity(key = Probe_Document(7))
			assert(identity_valid(current_identity()))
			if i == 0 {
				target: f32 = 0
				if current_frame().input.mouse_inside { target = 1 }
				identity_probe.amount = animate_f32(target, key = Probe_Animation(1), half_life = 1)
				paint(color = {identity_probe.amount, 0, 0, 1})
			}
			close_identity()
		}
		if !identity_probe.reorder { identity_probe.ids[3] = identity_probe_leaf(Probe_Document(8)) }
		// Same numeric value, different distinct/base types; signed and 128-bit keys.
		identity_probe.ids[4] = identity_probe_leaf(Probe_Panel(7))
		identity_probe.ids[5] = identity_probe_leaf(i64(7))
		identity_probe.ids[6] = identity_probe_leaf(u64(7))
		identity_probe.ids[7] = identity_probe_leaf(Probe_Document(-7))
		identity_probe.ids[8] = identity_probe_leaf(u128(1) << 100)
		// Separate caller locations forwarded through a wrapper stay distinct.
		identity_probe.ids[9] = identity_probe_location()
		identity_probe.ids[10] = identity_probe_location()
		for i in 0..<2 { identity_probe.ids[12 + i] = identity_probe_location() }
		// Rect and identity scopes can nest in either direction.
		open_identity(key = 99)
		open_rect(.Left, 10)
		identity_probe.ids[11] = current_identity()
		close_rect()
		close_identity()
	}
	close_rect()
}

@(private)
identity_probe_leaf :: proc(key: $T) -> Identity {
	id := open_identity(key = key)
	close_identity()
	return id
}

@(private)
identity_probe_location :: proc(loc := #caller_location) -> Identity {
	open_rect(.Top, 0, loc = loc)
	id := current_identity()
	close_rect()
	return id
}

@(private)
identity_churn_scene :: proc() {
	for i in 0..<64 {
		open_identity(key = identity_probe.parent * 64 + i)
		animate_f32(1)
		close_identity()
	}
}

@(private)
animation_cadence :: proc(t: ^testing.T) {
	// The same elapsed second at 30/60/120 callbacks gives the same result.
	for hz in ([]int{30, 60, 120}) {
		state := Frame_State{update = animation_cadence_scene}
		build_frame(nil, 0, {10, 10}, &state)
		state.frame.input.mouse_inside = true
		for i in 1..=hz { build_frame(nil, f64(i) / f64(hz), {10, 10}, &state) }
		testing.expect(t, math.abs(identity_probe.amount - 0.5) < 0.00001)
		destroy_frame_state(&state)
	}
}

@(private)
animation_cadence_scene :: proc() {
	target: f32 = 0
	if current_frame().input.mouse_inside { target = 1 }
	identity_probe.amount = animate_f32(target, half_life = 1)
}
