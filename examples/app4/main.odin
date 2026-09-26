package app4

import ui "../../core"
import "core:math"

// Rows, columns, and fit-sized backgrounds expose the computed bounds.
// The orange leaf changes width: its row and following siblings move with it.
// The right panel has an explicit width derived from the window. Narrowing it
// demonstrates overflow; automatic fill/shrink and clipping are later stages.
main :: proc() {
	ui.open_window("Odin UI Rebuilder — layout", 960, 640, update, frame_timing = .Summary)
}

update :: proc() {
	frame := ui.current_frame()
	orange_width := 140 + 60 * math.sin(f32(frame.time))

	ui.container_open({padding = ui.insets(24), gap = 24})
	{
		// A content-sized row. Its background grows with the animated leaf.
		ui.container_open({layout = .Row, padding = ui.insets(16), gap = 12,
			background = {0.12, 0.15, 0.20, 1}, corner_radius = 16})
		{
			box({orange_width, 48}, {0.98, 0.45, 0.20, 1})
			box({90, 64}, {0.22, 0.72, 0.94, 1})
			box({140, 32}, {0.53, 0.41, 0.92, 1})
		}
		ui.container_close()

		ui.container_open({layout = .Row, gap = 20})
		{
			// Width and height both come from the children plus padding/gaps.
			ui.container_open({padding = ui.insets(16), gap = 12,
				background = {0.12, 0.15, 0.20, 1}, corner_radius = 16})
			{
				box({120, 40}, {0.22, 0.78, 0.59, 1})
				box({80, 60}, {0.24, 0.56, 0.78, 1})
				box({100, 28}, {0.53, 0.41, 0.92, 1})
			}
			ui.container_close()

			ui.container_open({width = ui.fixed(max(frame.size.x - 220, 0)),
				padding = ui.insets(16), gap = 16,
				background = {0.16, 0.19, 0.25, 1}, corner_radius = 16})
			{
				ui.container_open({layout = .Row, padding = ui.insets(10), gap = 8,
					background = {0.08, 0.10, 0.14, 1}, corner_radius = 10})
				{
					box({64, 32}, {0.98, 0.75, 0.25, 1})
					box({96, 48}, {0.94, 0.38, 0.67, 1})
					box({48, 24}, {0.22, 0.72, 0.94, 1})
				}
				ui.container_close()

				ui.container_open({layout = .Row, gap = 12})
				{
					ui.container_open({padding = {left = 8, top = 16, right = 24, bottom = 8}, gap = 6,
						background = {0.08, 0.10, 0.14, 1}, corner_radius = 8})
					{
						box({84, 24}, {0.22, 0.78, 0.59, 1})
						box({48, 36}, {0.53, 0.41, 0.92, 1})
					}
					ui.container_close()
					box({72, 72}, {0.98, 0.45, 0.20, 1})
				}
				ui.container_close()
			}
			ui.container_close()
		}
		ui.container_close()
	}
	ui.container_close()
}

// A leaf follows the same explicit open/close convention as a parent.
box :: proc(size: [2]f32, color: ui.Color) {
	ui.container_open({width = ui.fixed(size.x), height = ui.fixed(size.y),
		background = color, corner_radius = 6})
	ui.container_close()
}
