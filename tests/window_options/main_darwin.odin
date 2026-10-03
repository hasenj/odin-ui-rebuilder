package window_options

import ui "../../core"
import "base:intrinsics"
import "core:fmt"
import "core:os"
import ns "core:sys/darwin/Foundation"
import mtk "vendor:darwin/MetalKit"

decorated, transparent: bool
attempts: int

// Separate executable because NSApplication/NSWindow must run on the main
// thread, whereas Odin's ordinary test runner executes tests on worker threads.
main :: proc() {
	assert(len(os.args) == 3)
	decorated = os.args[1] == "decorated"
	transparent = os.args[2] != "opaque"
	if os.args[2] == "default" {
		ui.open_window("Window options check", 240, 140, check_window, decorated = decorated)
	} else {
		ui.open_window("Window options check", 240, 140, check_window,
			decorated = decorated, transparent = transparent)
	}
}

check_window :: proc() {
	app := ns.Application.sharedApplication()
	window := intrinsics.objc_send(^ns.Window, app, "keyWindow")
	if window == nil {
		attempts += 1
		assert(attempts < 120, "Window failed to become key")
		return
	}
	style := intrinsics.objc_send(ns.WindowStyleMask, window, "styleMask")
	assert((.Titled in style) == decorated)
	assert(bool(intrinsics.objc_send(ns.BOOL, window, "canBecomeKeyWindow")))
	assert(bool(intrinsics.objc_send(ns.BOOL, window, "canBecomeMainWindow")))
	assert(bool(intrinsics.objc_send(ns.BOOL, window, "isOpaque")) == !transparent)
	assert(bool(intrinsics.objc_send(ns.BOOL, window, "isMovableByWindowBackground")) == !decorated)
	view := cast(^mtk.View)window->contentView()
	layer := intrinsics.objc_send(^ns.Layer, view, "layer")
	assert(bool(intrinsics.objc_send(ns.BOOL, view, "isOpaque")) == !transparent)
	assert(bool(intrinsics.objc_send(ns.BOOL, layer, "isOpaque")) == !transparent)
	clear := view->clearColor()
	assert(clear.alpha == (0 if transparent else 1))
	if transparent {
		assert(clear.red == 0 && clear.green == 0 && clear.blue == 0)
		background := intrinsics.objc_send(^ns.Color, window, "backgroundColor")
		assert(intrinsics.objc_send(ns.Float, background, "alphaComponent") == 0)
		assert(!bool(intrinsics.objc_send(ns.BOOL, window, "hasShadow")))
	}
	menu := intrinsics.objc_send(^ns.Menu, app, "mainMenu")
	assert(menu != nil)
	item := intrinsics.objc_send(^ns.MenuItem, menu, "itemAtIndex:", ns.Integer(0))
	submenu := item->submenu()
	assert(submenu != nil)
	quit := intrinsics.objc_send(^ns.MenuItem, submenu, "itemAtIndex:", ns.Integer(0))
	assert(string(quit->keyEquivalent()->UTF8String()) == "q")
	if !decorated { check_drag_region(window, view) }
	fmt.printf("Verified macOS window: decorated=%v, transparent=%v\n", decorated, transparent)
	os.exit(0)
}

// Exercise the real NSWindow event path, not only the stored region. Queue a
// release so AppKit's nested drag loop cannot wait for physical mouse input.
check_drag_region :: proc(window: ^ns.Window, view: ^mtk.View) {
	ui.window_drag_region({{40, 0}, {160, 36}})
	for point, i in ([3][2]f32{{20, 80}, {80, 18}, {220, 18}}) {
		p := ns.Point{ns.Float(point.x), ns.Float(point.y)}
		if !view->isFlipped() { p.y = view->bounds().size.height - p.y }
		p = intrinsics.objc_send(ns.Point, view, "convertPoint:toView:", p, cast(^ns.View)nil)
		up := mouse_event(window, .LeftMouseUp, p)
		intrinsics.objc_send(nil, ns.Application.sharedApplication(), "postEvent:atStart:", up, ns.BOOL(true))
		intrinsics.objc_send(nil, window, "sendEvent:", mouse_event(window, .LeftMouseDown, p))
		assert(bool(intrinsics.objc_send(ns.BOOL, window, "isMovableByWindowBackground")) == (i == 1),
			"Only the address area should drag; controls and file rows must receive ordinary clicks")
		intrinsics.objc_send(nil, window, "sendEvent:", up)
	}
}

mouse_event :: proc(window: ^ns.Window, kind: ns.EventType, point: ns.Point) -> ^ns.Event {
	return intrinsics.objc_send(^ns.Event, ns.Event,
		"mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:",
		kind, point, ns.EventModifierFlags{}, f64(0), intrinsics.objc_send(ns.Integer, window, "windowNumber"),
		rawptr(nil), ns.Integer(0), ns.Integer(1), f32(1))
}
