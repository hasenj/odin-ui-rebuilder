package demo4

import ui "../../core"
import "core:math"
import "core:fmt"

coast: ui.Image
loaded: bool

main :: proc() {
	ui.open_window("Odin UI Rebuilder — rect cutting", 960, 640, update, frame_timing = .Summary)
}

update :: proc() {
	if !loaded {
		err: ui.Image_Error
		// Run from the repository root; decode/upload once and retain the handle.
		coast, err = ui.load_image("examples/demo3/assets/coast.png")
		if err != nil {
			fmt.eprintln("Could not load coast image", err)
		}
		loaded = true
	}
	frame := ui.current_frame()
	ui.pad(20)
	// Paint first, then inset/cut. The background keeps its original geometry.
	ui.open_rect(direction = .Top, size = 90)
	{
		ui.paint(color = ui.hsl(220, 25, 16), corners = 12)
		ui.pad(12)
		ui.open_rect(.Left, 140 + 60 * math.sin(f32(frame.time)))
		{
			ui.paint(color = ui.hsl(20, 90, 58), corners = 8)
		}
		ui.close_rect()
		ui.pad4(0, 0, 0, 12)
		ui.open_rect(.Right, 90)
		{
			ui.paint(color = ui.hsl(260, 65, 65), corners = 8)
		}
		ui.close_rect()
		ui.pad4(0, 12, 0, 0)
		ui.paint(color = ui.hsl(195, 65, 52), corners = 8)
	}
	ui.close_rect()
	ui.pad4(16, 0, 0, 0)

	ui.open_rect(.Bottom, 36)
	{
		ui.paint(color = ui.hsl(220, 25, 16), corners = 8)
		ui.pad2(10, 16)
		ui.paint(color = ui.hsl(160, 45, 45), corners = 4)
	}
	ui.close_rect()
	ui.pad4(0, 0, 16, 0)

	ui.open_rect(.Left, 180)
	{
		ui.paint(color = ui.hsl(220, 25, 16), corners = 12)
		ui.pad(12)
		hues := [?]f32{160, 200, 260}
		for hue in hues {
			ui.open_rect(.Top, 52)
			{
				ui.paint(color = ui.hsl(hue, 50, 50), corners = 6)
			}
			ui.close_rect()
			ui.pad4(12, 0, 0, 0)
		}
	}
	ui.close_rect()

	// The main area's size is simply whatever remains after the cuts.
	ui.pad4(0, 0, 0, 16)
	ui.paint(color = ui.hsl(220, 20, 20), corners = 12)
	ui.pad(12)
	ui.paint(img = coast, corners = 8)
	// Further subdivision leaves the already emitted image untouched.
	ui.open_rect(.Bottom, 60)
	{
		ui.pad(8)
		ui.paint(color = ui.hsl(220, 25, 12, 0.85), corners = 6)
	}
	ui.close_rect()
}
