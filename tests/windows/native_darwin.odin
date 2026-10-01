package windows_test

import ui "../../core"
import "base:intrinsics"
import "base:runtime"
import ns "core:sys/darwin/Foundation"
import mtk "vendor:darwin/MetalKit"

pump: ^ns.Timer
pump_target: ns.id
pump_ticks: int
key_sent, key_seen, resized, resize_seen: bool

start_native_checks :: proc() {
	cls := ns.objc_lookUpClass("MultiWindowTestPump")
	if cls == nil {
		cls = ns.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "MultiWindowTestPump", 0)
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("tick:"), auto_cast pump_frames, "v@:@"))
		ns.objc_registerClassPair(cls)
	}
	pump_target = ns.class_createInstance(cls, 0)
	pump_ticks = 0
	pump = ns.Timer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeat(1.0 / 60, pump_target,
		intrinsics.objc_find_selector("tick:"), nil, true)
}

stop_native_checks :: proc() {
	intrinsics.objc_send(nil, pump, "invalidate")
	(cast(^ns.Object)pump_target)->release()
}

pump_frames :: proc "c" (_: ns.id, _: ns.SEL, _: ns.id) {
	context = runtime.default_context()
	pump_ticks += 1
	assert(pump_ticks < 600, "Multi-window test timed out")
	// Explicit draws let this check run even while the display is asleep.
	array := intrinsics.objc_send(^ns.Array, ns.Application.sharedApplication(), "windows")
	count := intrinsics.objc_send(ns.UInteger, array, "count")
	for i in 0..<count {
		window := intrinsics.objc_send(^ns.Window, array, "objectAtIndex:", i)
		view := cast(^mtk.View)window->contentView()
		view->draw()
	}
}

check_native_frame :: proc(index: int) {
	input := ui.current_frame().input
	if index != 0 { assert(.A not_in input.keys_down && .A not_in input.keys_pressed) }
	if index != 0 { return }
	if key_sent && .A in input.keys_pressed { key_seen = true }
	if resized && ui.current_frame().size == ([2]f32{420, 300}) { resize_seen = true }
	if counts[0] > 30 { assert(resize_seen, "Native resize did not reach the frame") }
	if counts[0] < 2 || key_sent { return }
	array := intrinsics.objc_send(^ns.Array, ns.Application.sharedApplication(), "windows")
	for i in 0..<intrinsics.objc_send(ns.UInteger, array, "count") {
		window := intrinsics.objc_send(^ns.Window, array, "objectAtIndex:", i)
		if string(intrinsics.objc_send(^ns.String, window, "title")->UTF8String()) != "Multi-window primary" { continue }
		intrinsics.objc_send(nil, window, "makeKeyWindow")
		intrinsics.objc_send(nil, window, "setContentSize:", ns.Size{420, 300})
		resized = true
		chars := ns.String.alloc()->initWithOdinString("a")
		defer chars->release()
		event := intrinsics.objc_send(^ns.Event, ns.Event,
			"keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:",
			ns.EventType.KeyDown, ns.Point{}, ns.EventModifierFlags{}, ns.TimeInterval(0),
			intrinsics.objc_send(ns.Integer, window, "windowNumber"), cast(ns.id)nil, chars, chars, ns.BOOL(false), u16(0))
		intrinsics.objc_send(nil, window, "sendEvent:", event)
		key_sent = true
	}
}

native_checks_complete :: proc() -> bool { return key_seen && resize_seen }

// Exercise the native close-button/delegate path, not just request_close.
close_replacement :: proc() {
	array := intrinsics.objc_send(^ns.Array, ns.Application.sharedApplication(), "windows")
	for i in 0..<intrinsics.objc_send(ns.UInteger, array, "count") {
		window := intrinsics.objc_send(^ns.Window, array, "objectAtIndex:", i)
		if string(intrinsics.objc_send(^ns.String, window, "title")->UTF8String()) == "Multi-window replacement" {
			intrinsics.objc_send(nil, window, "performClose:", cast(ns.id)nil)
			assert(!ui.window_alive(ui.current_window()))
			return
		}
	}
	panic("Replacement native window missing")
}

quit_application :: proc() {
	intrinsics.objc_send(nil, ns.Application.sharedApplication(), "terminate:", cast(ns.id)nil)
	assert(!ui.window_alive(ui.current_window()))
}
