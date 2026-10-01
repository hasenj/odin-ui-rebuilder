package platform

import ns "core:sys/darwin/Foundation"
import mtk "vendor:darwin/MetalKit"
import "base:intrinsics"
import "base:runtime"
import "core:time"
import "../core/primitives"

@(private)
mac_app: ^ns.Application
@(private)
mac_delegate: ns.id
@(private)
mac_context: runtime.Context

@(private)
application_init_impl :: proc() {
	ns.scoped_autoreleasepool()
	mac_context = context
	mac_app = ns.Application.sharedApplication()
	assert(mac_app != nil)
	if intrinsics.objc_send(ns.Integer, mac_app, "activationPolicy") != 0 {
		assert(mac_app->setActivationPolicy(.Regular))
	}
	cls := ns.objc_lookUpClass("OdinUIRebuilderApplicationDelegate")
	if cls == nil {
		cls = ns.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "OdinUIRebuilderApplicationDelegate", 0)
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("tick:"), auto_cast application_tick, "v@:@"))
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("applicationShouldTerminate:"), auto_cast application_quit, "Q@:@"))
		ns.objc_registerClassPair(cls)
	}
	mac_delegate = ns.class_createInstance(cls, 0)
	mac_app->setDelegate(cast(^ns.ApplicationDelegate)mac_delegate)
	install_application_menu(mac_app)
}

@(private)
application_shutdown_impl :: proc() {
	mac_app->setDelegate(nil)
	(cast(^ns.Object)mac_delegate)->release()
	mac_delegate = nil
}

@(private)
application_quit :: proc "c" (_: ns.id, _: ns.SEL, _: ns.id) -> ns.UInteger {
	context = mac_context
	for window in windows { if window != nil { window.closing = true } }
	return 0 // NSTerminateCancel: our loop returns after orderly destruction.
}

@(private)
application_tick :: proc "c" (_: ns.id, _: ns.SEL, _: ns.id) {
	context = mac_context
	service_windows()
	if window_count() == 0 && running {
		mac_app->stop(nil)
		// Wake AppKit's nextEvent wait so run returns even with no input.
		event := ns.Event.otherEventWithType(.ApplicationDefined, {}, {}, 0, 0, nil, 0, 0, 0)
		mac_app->postEvent(event, true)
	}
}

@(private)
application_run_impl :: proc() {
	ns.scoped_autoreleasepool()
	timer := ns.Timer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeat(1.0 / 60,
		mac_delegate, intrinsics.objc_find_selector("tick:"), nil, true)
	ns.RunLoop.mainRunLoop()->addTimerForMode(timer, ns.RunLoopCommonModes)
	defer intrinsics.objc_send(nil, timer, "invalidate")
	mac_app->activateIgnoringOtherApps(true)
	mac_app->run()
}

@(private)
create_window_impl :: proc(record: ^Window_Record) {
	ns.scoped_autoreleasepool()
	renderer := new(Metal_Renderer)
	renderer^ = {frame = record.frame, user_data = record.user_data, odin_context = context,
		input_state = record.input_state, window_handle = record.handle}
	renderer.profiler.mode = record.frame_timing
	renderer.profiler.window = record.handle
	record.native = renderer
	window := create_macos_window(record.width, record.height, record.decorated, record.transparent)
	renderer.window = window
	intrinsics.objc_send(nil, window, "setReleasedWhenClosed:", ns.BOOL(false))
	metal_init(renderer)
	renderer.view = allocate_metal_view()->initWithFrame(window->contentView()->bounds(), renderer.device)
	assert(renderer.view != nil)
	renderer.view->setColorPixelFormat(.BGRA8Unorm)
	configure_metal_transparency(renderer.view, record.transparent)
	renderer.view->setPreferredFramesPerSecond(60)
	renderer.view->setEnableSetNeedsDisplay(false)
	renderer.view->setPaused(false)
	intrinsics.objc_send(nil, renderer.view, "setAutoResizeDrawable:", ns.BOOL(true))
	window->setContentView(renderer.view)
	install_view_delegate(renderer)
	assert(bool(intrinsics.objc_send(ns.BOOL, window, "makeFirstResponder:", renderer.view)))
	renderer.start = time.tick_now()
	native_title := ns.String.alloc()->initWithOdinString(record.title)
	defer native_title->release()
	window->setTitle(native_title)
	window->center()
	// Cascade initial windows; subsequent resizing/positioning belongs to AppKit.
	bounds := intrinsics.objc_send(ns.Rect, window, "frame")
	offset := ns.Float((record.handle.index - 1) * 28)
	origin := ns.Point{bounds.origin.x + offset, bounds.origin.y + bounds.size.height - offset}
	intrinsics.objc_send(ns.Point, window, "cascadeTopLeftFromPoint:", origin)
	window->makeKeyAndOrderFront(nil)
}

@(private)
destroy_window_impl :: proc(record: ^Window_Record) {
	ns.scoped_autoreleasepool()
	renderer := cast(^Metal_Renderer)record.native
	renderer.view->setPaused(true)
	intrinsics.objc_send(nil, renderer.view, "setDelegate:", ns.id(nil))
	renderer.window->setDelegate(nil)
	intrinsics.objc_send(nil, renderer.window, "close")
	renderer.window->release()
	renderer.view->release()
	(cast(^ns.Object)renderer.delegate)->release()
	metal_destroy(renderer)
	free(renderer)
	record.native = nil
}

@(private)
window_should_close :: proc "c" (self: ns.id, _: ns.SEL, _: ns.id) -> ns.BOOL {
	renderer := (cast(^^Metal_Renderer)ns.object_getIndexedIvars(self))^
	context = renderer.odin_context
	request_close(renderer.window_handle)
	return false
}

@(private)
window_will_close :: proc "c" (self: ns.id, _: ns.SEL, _: ns.id) {
	renderer := (cast(^^Metal_Renderer)ns.object_getIndexedIvars(self))^
	context = renderer.odin_context
	request_close(renderer.window_handle)
}

@(private)
install_view_delegate :: proc(renderer: ^Metal_Renderer) {
	cls := ns.objc_lookUpClass("OdinUIRebuilderMetalDelegate")
	if cls == nil {
		cls = ns.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "OdinUIRebuilderMetalDelegate", 0)
		assert(cls != nil, "Could not register the Metal view delegate")
		draw_added := ns.class_addMethod(cls, intrinsics.objc_find_selector("drawInMTKView:"), auto_cast draw_frame, "v@:@")
		resize_added := ns.class_addMethod(cls, intrinsics.objc_find_selector("mtkView:drawableSizeWillChange:"), auto_cast drawable_size_changed, "v@:@{CGSize=dd}")
		assert(draw_added && resize_added, "Could not register Metal view callbacks")
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("windowDidResignKey:"), auto_cast window_resigned_key, "v@:@"))
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("windowDidBecomeKey:"), auto_cast window_became_key, "v@:@"))
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("windowShouldClose:"), auto_cast window_should_close, "B@:@"))
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("windowWillClose:"), auto_cast window_will_close, "v@:@"))
		ns.objc_registerClassPair(cls)
	}
	delegate := ns.class_createInstance(cls, size_of(^Metal_Renderer))
	assert(delegate != nil, "Could not create the Metal view delegate")
	(cast(^^Metal_Renderer)ns.object_getIndexedIvars(delegate))^ = renderer
	// Both native delegates are weak; renderer owns this allocation.
	renderer.delegate = delegate
	intrinsics.objc_send(nil, renderer.view, "setDelegate:", delegate)
	window := intrinsics.objc_send(^ns.Window, renderer.view, "window")
	window->setDelegate(cast(^ns.WindowDelegate)delegate)
}

@(private)
draw_frame :: proc "c" (self: ns.id, _: ns.SEL, view: ^mtk.View) {
	renderer := (cast(^^Metal_Renderer)ns.object_getIndexedIvars(self))^
	context = renderer.odin_context
	// Drawable acquisition may deliver a resize notification during this draw.
	// The current frame handles it; do not recursively invoke the UI update.
	if renderer.drawing || updating || servicing || !window_alive(renderer.window_handle) {
		return
	}
	renderer.drawing = true
	updating = true
	defer { renderer.drawing = false; updating = false }
	profiling := renderer.profiler.mode != .Disabled
	start, update_start: time.Tick
	update_ms: f64
	render_time: Render_Timing
	surfaces: []primitives.Surface
	if profiling {
		start = time.tick_now()
	}
	// This defer runs after the autorelease pool and temporary allocator cleanup.
	defer {
		if profiling {
			record_frame_timing(&renderer.profiler, start, update_ms, render_time, len(surfaces))
		}
	}
	ns.scoped_autoreleasepool()
	// Temporary app allocations last through submission of this frame only.
	defer free_all(context.temp_allocator)
	bounds := view->bounds()
	size := [2]f32{f32(bounds.size.width), f32(bounds.size.height)}
	sample_frame_input(renderer)
	if profiling {
		update_start = time.tick_now()
	}
	if renderer.frame != nil {
		elapsed := time.duration_seconds(time.tick_since(renderer.start))
		surfaces = renderer.frame(Renderer(renderer), elapsed, size, renderer.user_data)
	}
	if profiling {
		update_ms = time.duration_milliseconds(time.tick_since(update_start))
	}
	render(Renderer(renderer), surfaces, size, &render_time if profiling else nil)
}

@(private)
drawable_size_changed :: proc "c" (self: ns.id, _: ns.SEL, view: ^mtk.View, _: ns.Size) {
	renderer := (cast(^^Metal_Renderer)ns.object_getIndexedIvars(self))^
	context = renderer.odin_context
	renderer.resize_pending = true
	// Draw inside the resize transaction rather than waiting for the next timer
	// tick. Layout still uses logical view bounds, not drawable pixel dimensions.
	if !renderer.drawing {
		view->draw()
	}
}
