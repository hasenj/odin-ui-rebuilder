package ui

import "base:intrinsics"
import "core:math"

// Retain a scalar under the current identity. The call opens/closes a child
// identity, keyed by caller location or an explicit integer, like other nodes.
// First appearance starts at target. half_life is seconds to halve the remaining
// distance; changing target reverses smoothly from the previous value.
animate_f32 :: proc{animate_f32_implicit, animate_f32_keyed}

@(private)
Animation_F32 :: struct {value: f32, time: f64}

@(private)
animate_f32_implicit :: proc(target: f32, half_life: f32 = 0.06, loc := #caller_location) -> f32 {
	return animate_f32_key(target, half_life, Identity_Key{location = loc})
}

@(private)
animate_f32_keyed :: proc(target: f32, key: $T, half_life: f32 = 0.06) -> f32 where intrinsics.type_is_integer(T) {
	return animate_f32_key(target, half_life, integer_identity_key(key))
}

@(private)
animate_f32_key :: proc(target, half_life: f32, key: Identity_Key) -> f32 {
	assert(abs(target) <= max(f32), "Animation target must be finite")
	assert(half_life > 0 && half_life <= max(f32), "Animation half-life must be finite and positive")
	id := identity_enter(key, .Identity)
	defer close_identity()
	store := &active_state.identities
	now := current_frame().time
	state, found := store.animations[id]
	if !found {
		state = Animation_F32{target, now}
	} else {
		if state.value != target {
			dt := max(now - state.time, 0)
			// f64 intermediates also accommodate opposite extreme finite f32 values.
			weight := 1 - math.exp(-dt / f64(half_life) * 0.6931471805599453)
			state.value = f32(f64(state.value) + (f64(target) - f64(state.value)) * weight)
			if abs(f64(target) - f64(state.value)) <= 0.00001 * max(1, abs(f64(target))) {
				state.value = target
			}
		}
		state.time = max(now, state.time)
	}
	store.animations[id] = state
	return state.value
}
