package ui

// Geometry-only hover: no identity, capture, occlusion, or rounded-corner test.
// Without an argument, test the current remaining rect, just like paint().
hovered :: proc{hovered_current, hovered_rect}

@(private)
hovered_current :: proc() -> bool {
	return hovered_rect(current_rect())
}

@(private)
hovered_rect :: proc(rect: Rect) -> bool {
	frame := current_frame()
	if !frame.input.mouse_inside || rect.size.x <= 0 || rect.size.y <= 0 { return false }
	p := frame.input.mouse_position
	// Include top/left, exclude bottom/right so adjacent rects share no hit edge.
	return p.x >= rect.position.x && p.y >= rect.position.y &&
		p.x < rect.position.x + rect.size.x && p.y < rect.position.y + rect.size.y
}
