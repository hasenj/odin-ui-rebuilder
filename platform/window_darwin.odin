package platform

import ns "core:sys/darwin/Foundation"
import mtk "vendor:darwin/MetalKit"
import "base:intrinsics"
import "core:time"
import "core:fmt"
import "../core/primitives"
import "../core/input"

// Odin selects this implementation by the _darwin file suffix.
@(private)
open_window_impl :: proc(title: string, width, height: int, frame: Frame_Proc, user_data: rawptr, frame_timing: Frame_Timing, input_state: ^input.State) {
	app: ^ns.Application
	renderer := Metal_Renderer{frame = frame, user_data = user_data, odin_context = context}
	renderer.profiler.mode = frame_timing
	renderer.input_state = input_state
	{
		// Drain startup temporaries before entering AppKit's event loop, which
		// manages its own autorelease pools while processing events.
		ns.scoped_autoreleasepool()

		app = ns.Application.sharedApplication()
		assert(app != nil, "Could not create the macOS application")
		activated := app->setActivationPolicy(.Regular)
		assert(activated, "Could not activate the macOS application")

		// NSApplication does not retain its delegate. Keep this allocation alive
		// for the lifetime of the application.
		delegate := ns.application_delegate_register_and_alloc(
			{
				applicationShouldTerminateAfterLastWindowClosed = terminate_after_last_window_closed,
			},
			"OdinUIRebuilderApplicationDelegate",
			context,
		)
		assert(delegate != nil, "Could not create the macOS application delegate")
		app->setDelegate(delegate)

		window := ns.Window.alloc()->initWithContentRect(
			{size = {width = ns.Float(width), height = ns.Float(height)}},
			{.Titled, .Closable, .Miniaturizable, .Resizable},
			.Buffered,
			false,
		)
		assert(window != nil, "Could not create the macOS window")
		metal_init(&renderer)
		renderer.view = mtk.View.alloc()->initWithFrame(window->contentView()->bounds(), renderer.device)
		assert(renderer.view != nil, "Could not create the Metal view")
		renderer.view->setColorPixelFormat(.BGRA8Unorm)
		renderer.view->setClearColor({0.035, 0.045, 0.065, 1})
		renderer.view->setPreferredFramesPerSecond(60)
		renderer.view->setEnableSetNeedsDisplay(false)
		renderer.view->setPaused(false)
		// The bundled Odin binding has the wrong capitalization for this selector.
		intrinsics.objc_send(nil, renderer.view, "setAutoResizeDrawable:", ns.BOOL(true))
		window->setContentView(renderer.view)
		install_view_delegate(&renderer)
		renderer.start = time.tick_now()
		// NSWindow releases itself on close by default.
		native_title := ns.String.alloc()->initWithOdinString(title)
		defer native_title->release()
		window->setTitle(native_title)
		window->center()
		window->makeKeyAndOrderFront(nil)
		app->activateIgnoringOtherApps(true)
	}

	if frame_timing != .Disabled {
		fmt.println("[frame timing] CPU wall time; submit includes drawable waits. GPU execution and logging are excluded. Interval measures callback spacing; the first interval is 0.")
	}
	app->run()
}

@(private)
terminate_after_last_window_closed :: proc(_: ^ns.Application) -> ns.BOOL {
	return true
}

@(private)
install_view_delegate :: proc(renderer: ^Metal_Renderer) {
	cls := ns.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "OdinUIRebuilderMetalDelegate", 0)
	assert(cls != nil, "Could not register the Metal view delegate")
	draw_added := ns.class_addMethod(cls, intrinsics.objc_find_selector("drawInMTKView:"), auto_cast draw_frame, "v@:@")
	resize_added := ns.class_addMethod(cls, intrinsics.objc_find_selector("mtkView:drawableSizeWillChange:"), auto_cast drawable_size_changed, "v@:@{CGSize=dd}")
	assert(draw_added && resize_added, "Could not register Metal view callbacks")
	ns.objc_registerClassPair(cls)
	delegate := ns.class_createInstance(cls, size_of(^Metal_Renderer))
	assert(delegate != nil, "Could not create the Metal view delegate")
	(cast(^^Metal_Renderer)ns.object_getIndexedIvars(delegate))^ = renderer
	// MTKView's delegate is weak. This allocation lives until the app exits.
	intrinsics.objc_send(nil, renderer.view, "setDelegate:", delegate)
}

@(private)
draw_frame :: proc "c" (self: ns.id, _: ns.SEL, view: ^mtk.View) {
	renderer := (cast(^^Metal_Renderer)ns.object_getIndexedIvars(self))^
	context = renderer.odin_context
	// Drawable acquisition may deliver a resize notification during this draw.
	// The current frame handles it; do not recursively invoke the UI update.
	if renderer.drawing {
		return
	}
	renderer.drawing = true
	defer { renderer.drawing = false }
	profiling := renderer.profiler.mode != .Disabled
	start, update_start, submit_start: time.Tick
	update_ms, submit_ms: f64
	surfaces: []primitives.Surface
	if profiling {
		start = time.tick_now()
	}
	// This defer runs after the autorelease pool and temporary allocator cleanup.
	defer {
		if profiling {
			record_frame_timing(&renderer.profiler, start, update_ms, submit_ms, len(surfaces))
		}
	}
	ns.scoped_autoreleasepool()
	// Temporary app allocations last through submission of this frame only.
	defer free_all(context.temp_allocator)
	bounds := view->bounds()
	size := [2]f32{f32(bounds.size.width), f32(bounds.size.height)}
	sample_input(view, renderer.input_state)
	if profiling {
		update_start = time.tick_now()
	}
	if renderer.frame != nil {
		elapsed := time.duration_seconds(time.tick_since(renderer.start))
		surfaces = renderer.frame(Renderer(renderer), elapsed, size, renderer.user_data)
	}
	if profiling {
		submit_start = time.tick_now()
		update_ms = time.duration_milliseconds(time.tick_diff(update_start, submit_start))
	}
	render(Renderer(renderer), surfaces, size)
	if profiling {
		submit_ms = time.duration_milliseconds(time.tick_since(submit_start))
	}
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
