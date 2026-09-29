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
	fmt.printf("Verified macOS window: decorated=%v, transparent=%v\n", decorated, transparent)
	os.exit(0)
}
