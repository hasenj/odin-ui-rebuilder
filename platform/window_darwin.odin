package platform

import ns "core:sys/darwin/Foundation"
import mtk "vendor:darwin/MetalKit"
import "base:intrinsics"
import "base:runtime"

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
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("applicationDidBecomeActive:"), auto_cast application_became_active, "v@:@"))
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

// Startup activation can occur after all panels have already been ordered front.
// Keep the workspace's main role distinct from whichever panel is key.
@(private)
restore_main_window_role :: proc() {
	if !intrinsics.objc_send(ns.BOOL, mac_app, "isActive") { return }
	record := window_record(main_window)
	if record == nil || record.closing || record.native == nil { return }
	renderer := cast(^Metal_Renderer)record.native
	window := renderer.window
	if intrinsics.objc_send(ns.BOOL, window, "isVisible") &&
	   !intrinsics.objc_send(ns.BOOL, window, "isMiniaturized") &&
	   !intrinsics.objc_send(ns.BOOL, window, "isMainWindow") {
		intrinsics.objc_send(nil, window, "makeMainWindow")
	}
}

@(private)
application_became_active :: proc "c" (_: ns.id, _: ns.SEL, _: ns.id) {
	context = mac_context
	restore_main_window_role()
}

@(private)
application_quit :: proc "c" (_: ns.id, _: ns.SEL, _: ns.id) -> ns.UInteger {
	context = mac_context
	request_close(main_window)
	return 0 // NSTerminateCancel: our loop returns after orderly destruction.
}

@(private)
application_tick :: proc "c" (_: ns.id, _: ns.SEL, _: ns.id) {
	context = mac_context
	ns.scoped_autoreleasepool()
	application_cycle()
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
	renderer^ = {odin_context = context,
		input_state = record.input_state, window_handle = record.handle}
	record.native = renderer
	window := create_macos_window(record.width, record.height, record.decorated, record.transparent, record.panel)
	renderer.window = window
	intrinsics.objc_send(nil, window, "setReleasedWhenClosed:", ns.BOOL(false))
	metal_init(renderer)
	renderer.view = allocate_metal_view()->initWithFrame(window->contentView()->bounds(), renderer.device)
	assert(renderer.view != nil)
	renderer.view->setColorPixelFormat(.BGRA8Unorm)
	configure_metal_transparency(renderer.view, record.transparent)
	renderer.view->setPreferredFramesPerSecond(60)
	renderer.view->setEnableSetNeedsDisplay(false)
	renderer.view->setPaused(true)
	intrinsics.objc_send(nil, renderer.view, "setAutoResizeDrawable:", ns.BOOL(true))
	window->setContentView(renderer.view)
	install_view_delegate(renderer)
	assert(bool(intrinsics.objc_send(ns.BOOL, window, "makeFirstResponder:", renderer.view)))
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
	if !record.panel {
		// makeKeyAndOrderFront establishes keyboard focus, not main-window
		// status reliably during startup (before NSApplication.run).
		intrinsics.objc_send(nil, window, "makeMainWindow")
	}
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
	destroy_macos_text(&renderer.text_input)
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

// MetalKit calls only encode/present already-built output. The application timer
// owns UI updates, including for minimized/occluded windows with no drawable.
@(private)
draw_frame :: proc "c" (self: ns.id, _: ns.SEL, _: ^mtk.View) {
	renderer := (cast(^^Metal_Renderer)ns.object_getIndexedIvars(self))^
	context = renderer.odin_context
	if !renderer.presenting || renderer.drawing { return }
	record := window_record(renderer.window_handle)
	if record == nil { return }
	renderer.drawing = true
	defer { renderer.drawing = false }
	render(Renderer(renderer), record.surfaces, record.size, &record.render_time if record.frame_timing != .Disabled else nil)
}

@(private)
snapshot_window_impl :: proc(record: ^Window_Record) {
	renderer := cast(^Metal_Renderer)record.native
	bounds := renderer.view->bounds()
	record.size = {f32(bounds.size.width), f32(bounds.size.height)}
	record.renderer = Renderer(renderer)
	sample_frame_input(renderer)
}

@(private)
prepare_window_impl :: proc(record: ^Window_Record) {}

@(private)
present_window_impl :: proc(record: ^Window_Record) {
	renderer := cast(^Metal_Renderer)record.native
	if !intrinsics.objc_send(ns.BOOL, renderer.window, "isVisible") || intrinsics.objc_send(ns.BOOL, renderer.window, "isMiniaturized") { return }
	if intrinsics.objc_send(ns.UInteger, renderer.window, "occlusionState") & 2 == 0 { return }
	renderer.presenting = true
	defer { renderer.presenting = false }
	renderer.view->draw()
}

@(private)
drawable_size_changed :: proc "c" (self: ns.id, _: ns.SEL, _: ^mtk.View, _: ns.Size) {
	renderer := (cast(^^Metal_Renderer)ns.object_getIndexedIvars(self))^
	context = renderer.odin_context
	renderer.resize_pending = true
	// Resize transactions refresh the entire app, never just this window.
	application_cycle()
}
