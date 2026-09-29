package window_input

import "../../platform"
import "../../core/input"
import "../../core/primitives"
import "base:intrinsics"
import "core:fmt"
import "core:os"
import ns "core:sys/darwin/Foundation"
import cf "core:sys/darwin/CoreFoundation"

foreign import cg "system:CoreGraphics.framework"
foreign cg {
	CGEventCreateScrollWheelEvent2 :: proc(source: rawptr, units, count: u32, y, x, z: i32) -> rawptr ---
}

state: input.State
stage, attempts: int

// AppKit windows must run on the main thread, outside Odin's test workers.
// Dispatch real NSEvents to the production view, then observe the following
// frame snapshots. No global event injection or Accessibility access is needed.
main :: proc() {
	platform.open_window("Wheel input check", 240, 140, check_input, input_state = &state)
}

check_input :: proc(_: platform.Renderer, _: f64, _: [2]f32, _: rawptr) -> []primitives.Surface {
	window := intrinsics.objc_send(^ns.Window, ns.Application.sharedApplication(), "keyWindow")
	if window == nil {
		attempts += 1
		assert(attempts < 120, "Window failed to become key")
		return nil
	}
	view := window->contentView()
	switch stage {
	case 0:
		assert(state.scroll_delta == [2]f32{})
		send_scroll(view, true, -12, 7)
		send_scroll(view, true, -8, -3)
		// These were delivered after this update's input snapshot.
		assert(state.scroll_delta == [2]f32{})
	case 1:
		assert(state.scroll_delta == [2]f32{-4, 20}, "Precise wheel events must accumulate in logical points")
		send_scroll(view, false, -2, 1)
	case 2:
		assert(state.scroll_delta == [2]f32{-40, 80}, "Coarse wheel events must use logical line height")
	case 3:
		assert(state.scroll_delta == [2]f32{}, "Wheel movement must not repeat on idle frames")
		fmt.println("Verified macOS wheel: precise/coarse, both axes, event accumulation, next-frame delivery and idle reset")
		os.exit(0)
	}
	stage += 1
	return nil
}

send_scroll :: proc(view: ^ns.View, precise: bool, y, x: i32) {
	ref := CGEventCreateScrollWheelEvent2(nil, 0 if precise else 1, 2, y, x, 0)
	assert(ref != nil)
	defer cf.Release(cf.TypeRef(ref))
	event := intrinsics.objc_send(^ns.Event, ns.Event, "eventWithCGEvent:", ref)
	assert(event != nil)
	assert(bool(event->hasPreciseScrollingDeltas()) == precise)
	intrinsics.objc_send(nil, view, "scrollWheel:", event)
}
