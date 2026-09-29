package ui

import "core:testing"

@(private)
clip_pipeline :: proc(t: ^testing.T) {
	state := Frame_State{update = clip_scene}
	state.frame.input = {mouse_inside = true, mouse_position = {8, 8}}
	defer destroy_frame_state(&state)
	surfaces := build_frame(nil, 0, {100, 100}, &state)
	testing.expect_value(t, len(surfaces), 5)
	testing.expect(t, !surfaces[0].clip.enabled)
	testing.expect_value(t, surfaces[1].position, [2]f32{-10, -20})
	testing.expect_value(t, surfaces[1].clip.min, [2]f32{5, 5})
	testing.expect_value(t, surfaces[1].clip.max, [2]f32{35, 35})
	testing.expect_value(t, surfaces[2].clip.min, [2]f32{20, 20})
	testing.expect_value(t, surfaces[2].clip.max, [2]f32{35, 35})
	testing.expect_value(t, surfaces[2].background.r, f32(0)) // Pointer outside nested clip.
	testing.expect_value(t, surfaces[3].background.r, f32(1)) // Parent clip restored.
	testing.expect(t, !surfaces[4].clip.enabled)
	testing.expect_value(t, surfaces[4].position, [2]f32{}) // Parent geometry restored.
}

@(private)
clip_scene :: proc() {
	paint()
	open_clip(Rect{{5, 5}, {30, 30}})
	open_offset({-10, -20})
	paint()
	open_clip(Rect{{20, 20}, {60, 60}})
	// Low-level append gets the same clip as paint/text at the next boundary.
	append(&current_frame().surfaces, Surface{size = {100, 100}, background = {1 if hovered(current_rect()) else 0, 0, 0, 1}})
	close_clip()
	paint(color = {1 if hovered(current_rect()) else 0, 0, 0, 1})
	close_rect()
	close_clip()
	paint()
}
