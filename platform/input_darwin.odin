package platform

import "base:intrinsics"
import ns "core:sys/darwin/Foundation"
import mtk "vendor:darwin/MetalKit"
import "../core/input"

@(private)
metal_view_scroll_wheel :: proc "c" (self: ns.id, _: ns.SEL, event: ^ns.Event) {
	delegate := intrinsics.objc_send(ns.id, cast(^mtk.View)self, "delegate")
	if delegate == nil {
		return
	}
	renderer := (cast(^^Metal_Renderer)ns.object_getIndexedIvars(delegate))^
	context = renderer.odin_context
	// AppKit has already applied the user's natural-scroll preference. Precise
	// deltas are logical points, independent of the drawable's Retina scale.
	// Traditional wheels report lines; use 40 points per line for this host.
	unit: f32 = 1 if event->hasPreciseScrollingDeltas() else 40
	renderer.pending_scroll -= [2]f32{f32(event->scrollingDeltaX()), f32(event->scrollingDeltaY())} * unit
}

@(private)
sample_frame_input :: proc(renderer: ^Metal_Renderer) {
	// Drain before calling app code: events delivered during rendering belong
	// to the next update. Held pointer state is sampled separately.
	delta := renderer.pending_scroll
	renderer.pending_scroll = {}
	sample_input(renderer.view, renderer.input_state)
	if renderer.input_state != nil {
		renderer.input_state.scroll_delta = delta
	}
	sample_keyboard(&renderer.keyboard, renderer.input_state)
}

@(private)
metal_view_renderer :: proc "contextless" (self: ns.id) -> ^Metal_Renderer {
	delegate := intrinsics.objc_send(ns.id, cast(^mtk.View)self, "delegate")
	return (cast(^^Metal_Renderer)ns.object_getIndexedIvars(delegate))^ if delegate != nil else nil
}

@(private)
macos_modifiers :: proc(flags: ns.EventModifierFlags) -> input.Modifiers {
	result: input.Modifiers
	if .Shift in flags { result += {.Shift} }
	if .Control in flags { result += {.Control} }
	if .Option in flags { result += {.Alt} }
	if .Command in flags { result += {.Super} }
	return result
}

@(private)
macos_key :: proc(code: u16) -> (key: input.Key, ok: bool) {
	switch code {
	case 48: return .Tab, true
	case 36, 76: return .Enter, true
	case 49: return .Space, true
	case 53: return .Escape, true
	case 123: return .Left, true
	case 124: return .Right, true
	case 126: return .Up, true
	case 125: return .Down, true
	case 115: return .Home, true
	case 119: return .End, true
	case 51: return .Backspace, true
	case 117: return .Delete, true
	}
	return {}, false
}

@(private)
metal_view_key_down :: proc "c" (self: ns.id, _: ns.SEL, event: ^ns.Event) {
	renderer := metal_view_renderer(self)
	if renderer == nil { return }
	context = renderer.odin_context
	renderer.keyboard.modifiers = macos_modifiers(event->modifierFlags())
	if key, ok := macos_key(event->keyCode()); ok {
		// Repeated native keyDown events also produce one-frame presses.
		keyboard_press(&renderer.keyboard, key)
	}
}

@(private)
metal_view_key_up :: proc "c" (self: ns.id, _: ns.SEL, event: ^ns.Event) {
	renderer := metal_view_renderer(self)
	if renderer == nil { return }
	context = renderer.odin_context
	renderer.keyboard.modifiers = macos_modifiers(event->modifierFlags())
	if key, ok := macos_key(event->keyCode()); ok { keyboard_release(&renderer.keyboard, key) }
}

@(private)
metal_view_flags_changed :: proc "c" (self: ns.id, _: ns.SEL, event: ^ns.Event) {
	renderer := metal_view_renderer(self)
	if renderer == nil { return }
	context = renderer.odin_context
	renderer.keyboard.modifiers = macos_modifiers(event->modifierFlags())
}

@(private)
window_resigned_key :: proc "c" (self: ns.id, _: ns.SEL, _: ns.id) {
	renderer := (cast(^^Metal_Renderer)ns.object_getIndexedIvars(self))^
	context = renderer.odin_context
	keyboard_clear(&renderer.keyboard)
}

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

	// NSEvent's mask uses bit 0 for left and bit 1 for right. Map only the
	// supported buttons and replace the set so releases cannot leave stale flags.
	buttons := intrinsics.objc_send(ns.UInteger, ns.Event, "pressedMouseButtons")
	state.mouse_buttons = {}
	if buttons & 1 != 0 {
		state.mouse_buttons += {.Left}
	}
	if buttons & 2 != 0 {
		state.mouse_buttons += {.Right}
	}
}
