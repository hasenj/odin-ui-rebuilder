package ui

import "primitives"

@(private)
Hit_Entry :: struct {
	id: Identity,
	bounds: Rect,
	clip: primitives.Clip,
	layer: i32,
	depth: int,
	enabled: bool,
	focusable: bool,
	fence: bool,
}

@(private)
Interaction_Store :: struct {
	previous, current: [dynamic]Hit_Entry,
	previous_by_id: map[Identity]int,
	direct_hover: Identity,
	scrolls: map[Identity]Scroll_State,
	focused: Identity,
	fences: [dynamic]Focus_Fence,
	previous_buttons: Mouse_Buttons,
	revealed_focus: Identity,
}

// Disable pointer participation for the current rect (e.g. a decorative overlay).
// Descendants still participate unless explicitly disabled. Effective next frame.
set_hit_test :: proc(enabled: bool) {
	current_hit_entry().enabled = enabled
}

// The deepest eligible rect in the highest layer, resolved using the latest
// pointer snapshot against the preceding frame's geometry. Zero on no hit.
direct_hover :: proc() -> Identity {
	_ = current_frame()
	return active_state.interaction.direct_hover
}

@(private)
register_hit :: proc(id: Identity, bounds: Rect) -> int {
	store := &active_state.interaction
	index := len(store.current)
	append(&store.current, Hit_Entry{id = id, bounds = bounds, clip = current_clip(),
		layer = current_layer(), depth = len(active_state.identities.stack), enabled = true})
	return index
}

@(private)
interaction_begin :: proc() {
	store := &active_state.interaction
	clear(&store.current)
	store.direct_hover = {}
	if store.previous_by_id == nil { store.previous_by_id = make(map[Identity]int) }
	frame := current_frame()
	if frame.input.mouse_inside {
		best_layer: i32 = min(i32)
		best_depth := -1
		for entry in store.previous {
			if !entry.enabled || !hit_contains(entry, frame.input.mouse_position) { continue }
			if entry.layer > best_layer || (entry.layer == best_layer && entry.depth >= best_depth) {
				store.direct_hover, best_layer, best_depth = entry.id, entry.layer, entry.depth
			}
		}
	}
	route_scroll()
	resolve_focus_input()
	if store.focused != store.revealed_focus {
		reveal_focused_rect()
		store.revealed_focus = store.focused
	}
}

@(private)
hit_contains :: proc(entry: Hit_Entry, point: [2]f32) -> bool {
	return point_in_rect(point, entry.bounds) && point_in_clip(point, entry.clip)
}

@(private)
identity_descends_from :: proc(node, ancestor: Identity) -> bool {
	child := node
	for child != (Identity{}) && identity_valid(child) {
		if child == ancestor { return true }
		child = active_state.identities.nodes[child.index - 1].path.group.parent
	}
	return false
}

@(private)
interaction_end :: proc() {
	store := &active_state.interaction
	finish_focus()
	store.previous, store.current = store.current, store.previous
	reserve(&store.current, len(store.previous))
	clear(&store.previous_by_id)
	for entry, i in store.previous { store.previous_by_id[entry.id] = i }
	if !identity_valid(store.direct_hover) { store.direct_hover = {} }
	for id in store.scrolls {
		if !identity_valid(id) { delete_key(&store.scrolls, id) }
	}
}

@(private)
destroy_interaction :: proc(store: ^Interaction_Store) {
	delete(store.previous)
	delete(store.current)
	delete(store.previous_by_id)
	delete(store.scrolls)
	delete(store.fences)
}

@(private)
current_hit_entry :: proc() -> ^Hit_Entry {
	index: int
	if active_state.layout.active {
		store := &active_state.layout
		index = store.nodes[store.stack[len(store.stack) - 1]].hit
	} else { index = current_rect_context().hit_index }
	entry := &active_state.interaction.current[index]
	assert(entry.id == current_identity(), "Register rect properties while its identity is current")
	return entry
}
