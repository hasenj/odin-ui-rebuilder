package ui

// Identity-based hover includes ancestors of the direct hit. The current
// identity is the default; its original assigned bounds are used, not the
// remaining area after cuts/padding. No previous geometry means no hit yet.
// hovered(Rect) remains an explicit geometry-only query that ignores occlusion.
hovered :: proc{hovered_current, hovered_identity, hovered_rect}

@(private)
hovered_current :: proc() -> bool { return hovered_identity(current_identity()) }

@(private)
hovered_identity :: proc(id: Identity) -> bool {
	store := &active_state.interaction
	if !identity_descends_from(store.direct_hover, id) { return false }
	if index, ok := store.previous_by_id[id]; ok {
		return hit_contains(store.previous[index], current_frame().input.mouse_position)
	}
	// Logical scopes without a rect inherit their descendant's hover.
	return true
}

@(private)
hovered_rect :: proc(rect: Rect) -> bool {
	frame := current_frame()
	return frame.input.mouse_inside && point_in_rect(frame.input.mouse_position, rect) &&
		point_in_clip(frame.input.mouse_position, current_clip())
}

@(private)
point_in_rect :: proc(point: [2]f32, rect: Rect) -> bool {
	return rect.size.x > 0 && rect.size.y > 0 && point.x >= rect.position.x && point.y >= rect.position.y &&
		point.x < rect.position.x + rect.size.x && point.y < rect.position.y + rect.size.y
}
