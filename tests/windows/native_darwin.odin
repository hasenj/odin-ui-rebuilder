package windows_test

import ui "../../core"
import "core:fmt"
import "core:os"
import "base:intrinsics"
import "base:runtime"
import ns "core:sys/darwin/Foundation"
import mtk "vendor:darwin/MetalKit"

key_sent, key_seen, resize_seen, hidden_checked, stacking_checked, focus_roles_checked: bool
key_cycle, stacking_cycle: int

probe_timer: ^ns.Timer
probe_target: ns.id
probe_count: int

start_native_checks :: proc() {
	cls := ns.objc_lookUpClass("PanelDrawProbe")
	if cls == nil {
		cls = ns.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "PanelDrawProbe", 0)
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("tick:"), auto_cast probe_draws, "v@:@"))
		ns.objc_registerClassPair(cls)
	}
	probe_target = ns.class_createInstance(cls, 0)
	probe_timer = ns.Timer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeat(1.0 / 120,
		probe_target, intrinsics.objc_find_selector("tick:"), nil, true)
}

stop_native_checks :: proc() {
	intrinsics.objc_send(nil, probe_timer, "invalidate")
	(cast(^ns.Object)probe_target)->release()
}

// Out-of-cycle native draw requests must also leave every UI builder untouched.
probe_draws :: proc "c" (_: ns.id, _: ns.SEL, _: ns.id) {
	context = runtime.default_context()
	before := counts
	if window := native_window("Observer panel"); window != nil {
		view := cast(^mtk.View)window->contentView()
		view->draw()
		probe_count += 1
	}
	assert(counts == before)
}

native_window :: proc(title: string) -> ^ns.Window {
	array := intrinsics.objc_send(^ns.Array, ns.Application.sharedApplication(), "windows")
	for i in 0..<intrinsics.objc_send(ns.UInteger, array, "count") {
		window := intrinsics.objc_send(^ns.Window, array, "objectAtIndex:", i)
		if string(intrinsics.objc_send(^ns.String, window, "title")->UTF8String()) == title { return window }
	}
	return nil
}

check_native_frame :: proc(index: int) {
	frame := ui.current_frame()
	if index == 0 {
		window := native_window("Multi-window primary")
		assert(window != nil)
		// The first timer tick may precede native application activation.
		active := intrinsics.objc_send(ns.BOOL, ns.Application.sharedApplication(), "isActive")
		if active { assert_main_role(window) }
		if active && counts[0] >= 8 && stacking_cycle == 0 {
			// Raising/focusing the workspace must not bury its floating tools.
			window->makeKeyAndOrderFront(nil)
			assert(intrinsics.objc_send(ns.BOOL, window, "isKeyWindow"))
			observer := native_window("Observer panel")
			assert(intrinsics.objc_send(ns.BOOL, observer, "isVisible"))
			// Place the panel inside the workspace and inspect the actual front
			// window at their overlap (NSApplication.orderedWindows excludes panels).
			bounds := intrinsics.objc_send(ns.Rect, window, "frame")
			origin := ns.Point{bounds.origin.x + 20, bounds.origin.y + 20}
			intrinsics.objc_send(nil, observer, "setFrameOrigin:", origin)
			stacking_cycle = counts[0]
		}
		if active && stacking_cycle > 0 && counts[0] > stacking_cycle && !stacking_checked {
			observer := native_window("Observer panel")
			bounds := intrinsics.objc_send(ns.Rect, observer, "frame")
			point := ns.Point{bounds.origin.x + 40, bounds.origin.y + 40}
			front := intrinsics.objc_send(ns.Integer, ns.Window, "windowNumberAtPoint:belowWindowWithWindowNumber:", point, ns.Integer(0))
			panel_number := intrinsics.objc_send(ns.Integer, observer, "windowNumber")
			// AppKit returns before the window server applies ordering/moves.
			// A single frame is not always enough, especially after another GUI test.
			if front != panel_number && counts[0] - stacking_cycle >= 60 {
				fmt.eprintf("Panel stacking mismatch after settling: front=%v panel=%v main=%v\n", front, panel_number, intrinsics.objc_send(ns.Integer, window, "windowNumber"))
				os.exit(1)
			}
			stacking_checked = front == panel_number
		}
		if active && stacking_checked && !focus_roles_checked {
			observer := native_window("Observer panel")
			intrinsics.objc_send(nil, observer, "makeKeyWindow")
			assert(intrinsics.objc_send(ns.BOOL, observer, "isKeyWindow"))
			assert(!intrinsics.objc_send(ns.BOOL, window, "isKeyWindow"))
			assert_main_role(window)
			focus_roles_checked = true
		}
		if frame.size == ([2]f32{420, 300}) { resize_seen = true }
		if counts[0] == 2 { intrinsics.objc_send(nil, window, "setContentSize:", ns.Size{420, 300}) }
		if active && counts[0] >= 2 && !key_sent {
			observer := native_window("Observer panel")
			assert(observer != nil)
			intrinsics.objc_send(nil, observer, "makeKeyWindow")
			assert_main_role(window)
			chars := ns.String.alloc()->initWithOdinString("a")
			defer chars->release()
			event := intrinsics.objc_send(^ns.Event, ns.Event,
				"keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:",
				ns.EventType.KeyDown, ns.Point{}, ns.EventModifierFlags{}, ns.TimeInterval(0),
				intrinsics.objc_send(ns.Integer, observer, "windowNumber"), cast(ns.id)nil, chars, chars, ns.BOOL(false), u16(0))
			intrinsics.objc_send(nil, observer, "sendEvent:", event)
			key_sent = true
			key_cycle = counts[0]
		}
		assert(.A not_in frame.input.keys_pressed)
	} else {
		title := "Multi-window secondary" if index == 1 else "Multi-window replacement" if index == 2 else "Observer panel"
		window := native_window(title)
		assert(window != nil)
		assert(intrinsics.objc_send(ns.Integer, window, "tabbingMode") == 2)
		assert(!intrinsics.objc_send(ns.BOOL, window, "canBecomeMainWindow"))
		assert(!intrinsics.objc_send(ns.BOOL, window, "isMainWindow"))
		assert(intrinsics.objc_send(ns.BOOL, window, "isFloatingPanel"))
		assert(intrinsics.objc_send(ns.BOOL, window, "hidesOnDeactivate"))
		assert(intrinsics.objc_send(ns.WindowLevel, window, "level") == .Floating)
		style := intrinsics.objc_send(ns.WindowStyleMask, window, "styleMask")
		assert((.Titled in style) == (index == 2))
		if index == 3 {
			if key_sent && counts[0] == key_cycle { assert(.A not_in frame.input.keys_pressed, "Input was sampled after another builder ran") }
			if key_sent && counts[0] == key_cycle + 1 { key_seen = .A in frame.input.keys_pressed; assert(key_seen) }
			if counts[3] == 4 { intrinsics.objc_send(nil, window, "orderOut:", cast(ns.id)nil) }
			if counts[3] == 7 {
				assert(!intrinsics.objc_send(ns.BOOL, window, "isVisible"))
				hidden_checked = true
				window->makeKeyAndOrderFront(nil)
			}
		}
	}
	// Extra native draw requests during a cycle must not enter any UI builder.
	before := counts
	array := intrinsics.objc_send(^ns.Array, ns.Application.sharedApplication(), "windows")
	for i in 0..<intrinsics.objc_send(ns.UInteger, array, "count") {
		window := intrinsics.objc_send(^ns.Window, array, "objectAtIndex:", i)
		view := cast(^mtk.View)window->contentView()
		view->draw()
	}
	assert(counts == before)
}

native_checks_complete :: proc() -> bool { return key_seen && resize_seen && hidden_checked && probe_count > 0 && stacking_checked && focus_roles_checked }

close_replacement :: proc() {
	window := native_window("Multi-window replacement")
	assert(window != nil)
	intrinsics.objc_send(nil, window, "performClose:", cast(ns.id)nil)
	assert(!ui.panel_alive(ui.current_window()))
}

close_main :: proc() {
	window := native_window("Multi-window primary")
	intrinsics.objc_send(nil, window, "performClose:", cast(ns.id)nil)
	assert(!ui.window_alive(ui.current_window()))
}

quit_application :: proc() {
	intrinsics.objc_send(nil, ns.Application.sharedApplication(), "terminate:", cast(ns.id)nil)
	assert(!ui.window_alive(ui.current_window()))
}

assert_main_role :: proc(window: ^ns.Window) {
	if !intrinsics.objc_send(ns.BOOL, window, "isMainWindow") {
		fmt.eprintf("Main role missing: counts=%v active=%v visible=%v key=%v canMain=%v appMain=%v\n", counts,
			intrinsics.objc_send(ns.BOOL, ns.Application.sharedApplication(), "isActive"),
			intrinsics.objc_send(ns.BOOL, window, "isVisible"),
			intrinsics.objc_send(ns.BOOL, window, "isKeyWindow"),
			intrinsics.objc_send(ns.BOOL, window, "canBecomeMainWindow"),
			intrinsics.objc_send(^ns.Window, ns.Application.sharedApplication(), "mainWindow"))
		os.exit(1)
	}
	assert(intrinsics.objc_send(^ns.Window, ns.Application.sharedApplication(), "mainWindow") == window)
}
