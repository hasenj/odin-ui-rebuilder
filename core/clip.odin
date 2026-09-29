package ui

import "primitives"

@(private)
Clip_Scope :: struct {clip: primitives.Clip}

// Restrict subsequent painting and pointer tests. Nested clips intersect in
// window coordinates; padding/cutting inside the scope does not move the clip.
// Clipping does not create an identity or change layout geometry.
open_clip :: proc{open_clip_current, open_clip_rect}

@(private)
open_clip_current :: proc() { open_clip_rect(current_rect()) }

@(private)
open_clip_rect :: proc(rect: Rect) {
	assert(valid_length(rect.size.x) && valid_length(rect.size.y), "Invalid clip extent")
	flush_surface_state()
	clip := primitives.Clip{true, rect.position, rect.position + rect.size}
	parent := current_clip()
	if parent.enabled {
		for axis in 0..<2 {
			clip.min[axis] = max(clip.min[axis], parent.min[axis])
			clip.max[axis] = min(clip.max[axis], parent.max[axis])
		}
	}
	append(&active_state.clips, Clip_Scope{clip})
}

close_clip :: proc() {
	assert(active_state != nil && len(active_state.clips) > 0, "Unbalanced close_clip")
	flush_surface_state()
	pop(&active_state.clips)
}

@(private)
current_clip :: proc() -> primitives.Clip {
	if len(active_state.clips) == 0 { return {} }
	return active_state.clips[len(active_state.clips) - 1].clip
}

// Stamp only the newly emitted range when visual state changes. This includes
// text glyphs and low-level appends without walking the same surfaces per parent.
@(private)
flush_surface_state :: proc() {
	state := active_state
	clip := current_clip()
	for &surface in state.frame.surfaces[state.surface_cursor:] {
		if clip.enabled {
			if surface.clip.enabled {
				for axis in 0..<2 {
					surface.clip.min[axis] = max(surface.clip.min[axis], clip.min[axis])
					surface.clip.max[axis] = min(surface.clip.max[axis], clip.max[axis])
				}
			} else {
				surface.clip = clip
			}
		}
	}
	if len(state.frame.surfaces) > state.surface_cursor {
		append(&state.surface_runs, Surface_Run{state.surface_cursor, len(state.frame.surfaces), current_layer()})
	}
	state.surface_cursor = len(state.frame.surfaces)
}

@(private)
point_in_clip :: proc(point: [2]f32, clip: primitives.Clip) -> bool {
	return !clip.enabled || (point.x >= clip.min.x && point.y >= clip.min.y && point.x < clip.max.x && point.y < clip.max.y)
}
