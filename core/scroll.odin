package ui

import "base:intrinsics"

Scroll_State :: struct {
	offset: [2]f32, // Positive towards the content's right/bottom.
	max_offset: [2]f32,
	viewport: Rect,
	content_size: [2]f32,
	layout_offset: [2]f32, // Offset used by the previous/current built geometry.
}

// Enter a clipped content canvas with retained offsets under a stable identity.
// Content extent is explicit and at least the viewport extent on each axis.
// Children use ordinary rect cuts; close with close_scroll(), not close_rect().
open_scroll :: proc{open_scroll_implicit, open_scroll_keyed}

@(private)
open_scroll_implicit :: proc(content_size: [2]f32, loc := #caller_location) {
	open_scroll_key(content_size, Identity_Key{location = loc})
}

@(private)
open_scroll_keyed :: proc(content_size: [2]f32, key: $T) where intrinsics.type_is_integer(T) {
	open_scroll_key(content_size, integer_identity_key(key))
}

@(private)
open_scroll_key :: proc(content_size: [2]f32, key: Identity_Key) {
	assert(valid_length(content_size.x) && valid_length(content_size.y), "Invalid scroll content size")
	viewport := current_rect()
	open_clip(viewport)
	open_rect_at_key(viewport, key)
	store := &active_state.interaction
	if store.scrolls == nil { store.scrolls = make(map[Identity]Scroll_State) }
	id := current_identity()
	state := store.scrolls[id]
	state.viewport = viewport
	for axis in 0..<2 {
		state.content_size[axis] = max(content_size[axis], viewport.size[axis])
		state.max_offset[axis] = state.content_size[axis] - viewport.size[axis]
		state.offset[axis] = clamp(state.offset[axis], 0, state.max_offset[axis])
	}
	state.layout_offset = state.offset
	store.scrolls[id] = state
	current_rect_context().remaining = Rect{viewport.position - state.offset, state.content_size}
	current_rect_context().scroll_clip_depth = len(active_state.clips)
	stack := &active_state.identities.stack
	stack[len(stack) - 1].kind = .Scroll
}

close_scroll :: proc() {
	assert(len(active_state.clips) == current_rect_context().scroll_clip_depth, "Unclosed clip inside scroll")
	identity_leave(.Scroll)
	pop(&active_state.rects)
	close_clip()
}

// Snapshot for the current scroll scope. Its viewport stays fixed as content moves.
current_scroll :: proc() -> Scroll_State {
	state, ok := active_state.interaction.scrolls[current_identity()]
	assert(ok, "Not in a scroll scope")
	return state
}

// Apply before building children (for programmatic reveal or a scrollbar).
// Values clamp to the content extent. Does not consume or mutate raw input.
scroll_to :: proc(offset: [2]f32) {
	assert(abs(offset.x) <= max(f32) && abs(offset.y) <= max(f32), "Invalid scroll offset")
	state := current_scroll()
	old := state.offset
	for axis in 0..<2 { state.offset[axis] = clamp(offset[axis], 0, state.max_offset[axis]) }
	state.layout_offset = state.offset
	active_state.interaction.scrolls[current_identity()] = state
	current_rect_context().remaining.position += old - state.offset
}

// Route each axis independently, from the topmost/deepest hit through its
// ancestors. An inner region consumes only movement it can actually perform;
// remaining movement chains to outer regions. The raw snapshot remains intact.
@(private)
route_scroll :: proc() {
	store := &active_state.interaction
	delta := current_frame().input.scroll_delta
	assert(abs(delta.x) <= max(f32) && abs(delta.y) <= max(f32), "Invalid scroll delta")
	id := store.direct_hover
	for id != (Identity{}) && identity_valid(id) {
		if state, ok := store.scrolls[id]; ok {
			if hit_index, found := store.previous_by_id[id]; found && hit_contains(store.previous[hit_index], current_frame().input.mouse_position) {
				for axis in 0..<2 {
					old := state.offset[axis]
					state.offset[axis] = f32(clamp(f64(old) + f64(delta[axis]), 0, f64(state.max_offset[axis])))
					delta[axis] -= state.offset[axis] - old
				}
				store.scrolls[id] = state
			}
		}
		id = active_state.identities.nodes[id.index - 1].path.group.parent
	}
}

// Scroll the newly focused rect into view, from inner to outer scroll regions.
// Only focus changes trigger this: manual scrolling can move an unchanged focus
// owner offscreen without the framework immediately snapping it back.
@(private)
reveal_focused_rect :: proc() {
	store := &active_state.interaction
	index, ok := store.previous_by_id[store.focused]
	if !ok || !identity_valid(store.focused) { return }
	bounds := store.previous[index].bounds
	id := active_state.identities.nodes[store.focused.index - 1].path.group.parent
	for identity_valid(id) {
		if state, found := store.scrolls[id]; found {
			bounds.position -= state.offset - state.layout_offset
			for axis in 0..<2 {
				delta: f32
				if bounds.position[axis] < state.viewport.position[axis] || bounds.size[axis] > state.viewport.size[axis] {
					delta = bounds.position[axis] - state.viewport.position[axis]
				} else if bounds.position[axis] + bounds.size[axis] > state.viewport.position[axis] + state.viewport.size[axis] {
					delta = bounds.position[axis] + bounds.size[axis] - state.viewport.position[axis] - state.viewport.size[axis]
				}
				old := state.offset[axis]
				state.offset[axis] = clamp(old + delta, 0, state.max_offset[axis])
				bounds.position[axis] -= state.offset[axis] - old
			}
			store.scrolls[id] = state
		}
		id = active_state.identities.nodes[id.index - 1].path.group.parent
	}
}
