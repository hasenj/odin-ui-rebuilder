package platform

import "base:intrinsics"
import ns "core:sys/darwin/Foundation"
import "../core/input"

@(private)
sample_input :: proc(view: ^ns.View, state: ^input.State) {
	if state == nil {
		return
	}
	window := intrinsics.objc_send(^ns.Window, view, "window")
	if window == nil {
		state^ = {}
		return
	}
	// Poll current state rather than retaining the last mouse-moved event. This
	// also tracks a stationary pointer correctly when the window moves/resizes.
	point := window->convertPointFromScreen(ns.Event.mouseLocation())
	point = view->convertPointFromView(point, nil)
	bounds := view->bounds()
	x := f32(point.x - bounds.origin.x)
	y := f32(point.y - bounds.origin.y)
	if !view->isFlipped() {
		y = f32(bounds.size.height) - y
	}
	state.mouse_position = {x, y}
	state.mouse_inside = x >= 0 && y >= 0 && x < f32(bounds.size.width) && y < f32(bounds.size.height)
}
