package ui

@(private)
Focus_Fence :: struct {id, restore: Identity}

// Register the current rect in declaration-order keyboard traversal. Disabled
// entries remain drawable and hoverable but are skipped by click/Tab focus.
focusable :: proc(enabled: bool = true) {
	current_hit_entry().focusable = enabled
}

// Confine keyboard focus to this identity's descendants while it is declared.
// Highest layer/deepest/latest fence wins. Removing it restores earlier focus
// if that node still exists. Pointer blocking is a separate layer/hit-test choice.
focus_fence :: proc() {
	current_hit_entry().fence = true
}

focused :: proc{focused_current, focused_identity}
@(private)
focused_current :: proc() -> bool { return focused_identity(current_identity()) }
@(private)
focused_identity :: proc(id: Identity) -> bool {
	return identity_descends_from(direct_focus(), id)
}

direct_focus :: proc() -> Identity {
	_ = current_frame()
	return active_state.interaction.focused
}

request_focus :: proc{request_focus_current, request_focus_identity}
@(private)
request_focus_current :: proc() { request_focus_identity(current_identity()) }
@(private)
request_focus_identity :: proc(id: Identity) {
	assert(identity_valid(id), "Cannot focus an invalid identity")
	if focus_allowed(id) { active_state.interaction.focused = id }
}

clear_focus :: proc() { active_state.interaction.focused = {} }

@(private)
focus_allowed :: proc(id: Identity) -> bool {
	fences := active_state.interaction.fences[:]
	return len(fences) == 0 || identity_descends_from(id, fences[len(fences) - 1].id)
}

@(private)
resolve_focus_input :: proc() {
	store := &active_state.interaction
	input := current_frame().input
	pressed := input.mouse_pressed | (input.mouse_buttons & ~store.previous_buttons)
	store.previous_buttons = input.mouse_buttons
	if .Left in pressed && input.mouse_inside {
		id := store.direct_hover
		if focus_allowed(id) {
			store.focused = {}
			for identity_valid(id) {
				if index, ok := store.previous_by_id[id]; ok && store.previous[index].focusable {
					store.focused = id
					break
				}
				id = active_state.identities.nodes[id.index - 1].path.group.parent
			}
		}
	}
	if .Tab in input.keys_pressed && (input.modifiers & ~Modifiers{.Shift}) == (Modifiers{}) {
		count := len(store.previous)
		index := -1
		for entry, i in store.previous { if entry.id == store.focused { index = i; break } }
		reverse := .Shift in input.modifiers
		if index < 0 && reverse { index = 0 }
		for _ in 0..<count {
			index = (index + count + (-1 if reverse else 1)) % count
			entry := store.previous[index]
			if entry.focusable && focus_allowed(entry.id) && entry.bounds.size.x > 0 && entry.bounds.size.y > 0 {
				store.focused = entry.id
				break
			}
		}
	}
}

@(private)
finish_focus :: proc() {
	store := &active_state.interaction
	fence: Identity
	best_layer: i32 = min(i32)
	best_depth := -1
	for entry in store.current {
		if entry.fence && (entry.layer > best_layer || (entry.layer == best_layer && entry.depth >= best_depth)) {
			fence, best_layer, best_depth = entry.id, entry.layer, entry.depth
		}
	}
	// Retain a stack of prior focus owners so nested modal fences restore in order.
	for len(store.fences) > 0 {
		top := store.fences[len(store.fences) - 1]
		present := false
		for entry in store.current { if entry.id == top.id && entry.fence { present = true; break } }
		if present { break }
		store.focused = pop(&store.fences).restore
	}
	found := -1
	for item, i in store.fences { if item.id == fence { found = i; break } }
	if found >= 0 {
		for len(store.fences) > found + 1 { store.focused = pop(&store.fences).restore }
	} else if fence != (Identity{}) {
		append(&store.fences, Focus_Fence{fence, store.focused})
	}
	valid := false
	first: Identity
	for entry in store.current {
		if !entry.focusable || entry.bounds.size.x <= 0 || entry.bounds.size.y <= 0 || !focus_allowed(entry.id) { continue }
		if first == (Identity{}) { first = entry.id }
		if entry.id == store.focused { valid = true }
	}
	if !valid { store.focused = first if fence != (Identity{}) else Identity{} }
}
