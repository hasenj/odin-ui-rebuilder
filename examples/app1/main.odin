package app1

import ui "../../core"
import "core:math"

main :: proc() {
	// Use -define:PROFILE_EVERY_FRAME=true to print individual frame timings.
	timing: ui.Frame_Timing = .Every_Frame when #config(PROFILE_EVERY_FRAME, false) else .Summary
	ui.open_window("Odin UI Rebuilder — surfaces", 960, 640, update, frame_timing = timing)
}

update :: proc() {
	frame := ui.current_frame()
	t := f32(frame.time)
	// A stationary background primitive makes the moving shapes easy to read.
	append(&frame.surfaces, ui.Surface{
		position = {24, 24}, size = {max(frame.size.x - 48, 0), max(frame.size.y - 48, 0)},
		background = {0.07, 0.09, 0.13, 1}, corner_radius = 24,
	})
	colors := [?]ui.Color{
		{0.20, 0.72, 0.94, 1}, {0.98, 0.42, 0.33, 1},
		{0.49, 0.38, 0.95, 0.8}, {0.22, 0.83, 0.62, 1},
		{0.98, 0.77, 0.25, 0.85}, {0.94, 0.38, 0.67, 0.75},
	}
	sizes := [?][2]f32{{160, 100}, {90, 90}, {200, 68}, {72, 160}, {140, 140}, {240, 56}}
	radii := [?]f32{0, 18, 34, 12, 70, 28}
	for color, i in colors {
		phase := f32(i) * 1.13
		travel := [2]f32{max(frame.size.x - sizes[i].x - 96, 0), max(frame.size.y - sizes[i].y - 96, 0)}
		position := [2]f32{
			48 + travel.x * (0.5 + 0.5 * math.sin(t * (0.45 + f32(i) * 0.035) + phase)),
			48 + travel.y * (0.5 + 0.5 * math.cos(t * 0.38 + phase * 1.7)),
		}
		append(&frame.surfaces, ui.Surface{
			position = position, size = sizes[i], background = color, corner_radius = radii[i],
		})
	}
}
