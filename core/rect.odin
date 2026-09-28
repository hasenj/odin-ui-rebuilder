package ui

import "base:intrinsics"

// Window-relative logical points, origin at the top left, Y increasing downwards.
Rect :: struct {position, size: [2]f32}
Direction :: enum u8 {Top, Right, Bottom, Left}

@(private)
Rect_Context :: struct {bounds, remaining: Rect}

// Returns a value snapshot, safe to keep while opening or closing other rects.
current_rect :: proc() -> Rect {
	return current_rect_context().remaining
}

// The area originally assigned to this scope, before padding or child cuts.
current_bounds :: proc() -> Rect {
	return current_rect_context().bounds
}

// Consume a strip from the current remaining area, then enter that strip.
// Top/Bottom sizes are heights; Left/Right sizes are widths. Oversized cuts
// consume all available space. Even a zero-sized cut must be closed.
open_rect :: proc{open_rect_implicit, open_rect_keyed}

@(private)
open_rect_implicit :: proc(direction: Direction, size: f32, loc := #caller_location) {
	open_rect_with_key(direction, size, Identity_Key{location = loc})
}

@(private)
open_rect_keyed :: proc(direction: Direction, size: f32, key: $T) where intrinsics.type_is_integer(T) {
	open_rect_with_key(direction, size, integer_identity_key(key))
}

@(private)
open_rect_with_key :: proc(direction: Direction, size: f32, key: Identity_Key) {
	assert(valid_length(size), "Cut size must be finite and nonnegative")
	parent := current_rect_context()
	axis := 1 if direction == .Top || direction == .Bottom else 0
	amount := min(size, parent.remaining.size[axis])
	cut := parent.remaining
	cut.size[axis] = amount
	parent.remaining.size[axis] -= amount
	if direction == .Top || direction == .Left {
		parent.remaining.position[axis] += amount
	} else {
		cut.position[axis] += parent.remaining.size[axis]
	}
	// Appending can relocate the stack; do not use parent after this point.
	append(&active_state.rects, Rect_Context{bounds = cut, remaining = cut})
	identity_enter(key, .Rect)
}

// Return to the already-reduced parent. Child padding/cuts cannot affect it.
close_rect :: proc() {
	assert(active_state != nil, "Rect calls must run inside the window update")
	assert(len(active_state.rects) > 1, "Unbalanced close_rect")
	identity_leave(.Rect)
	pop(&active_state.rects)
}

pad :: proc(all: f32) {
	pad4(all, all, all, all)
}

// CSS order: vertical, horizontal.
pad2 :: proc(vertical, horizontal: f32) {
	pad4(vertical, horizontal, vertical, horizontal)
}

// CSS order: top, right, bottom, left. Insets saturate at the remaining extent:
// left/top consume first, then right/bottom. The result stays inside its old rect.
// Padding changes remaining space only, never original bounds or emitted paint.
pad4 :: proc(top, right, bottom, left: f32) {
	assert(valid_length(top) && valid_length(right) && valid_length(bottom) && valid_length(left), "Padding must be finite and nonnegative")
	r := &current_rect_context().remaining
	leading := [2]f32{min(left, r.size.x), min(top, r.size.y)}
	r.position += leading
	r.size -= leading
	r.size -= [2]f32{min(right, r.size.x), min(bottom, r.size.y)}
}

@(private)
current_rect_context :: proc() -> ^Rect_Context {
	assert(active_state != nil, "Rect calls must run inside the window update")
	return &active_state.rects[len(active_state.rects) - 1]
}

@(private)
valid_length :: proc(value: f32) -> bool {
	return value >= 0 && value <= max(f32)
}
