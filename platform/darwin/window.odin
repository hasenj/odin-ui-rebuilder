package darwin

import ns "core:sys/darwin/Foundation"

// Owns the native application, window, and event loop. No native types escape
// this package. AppKit terminates the process when the last window closes.
open_window :: proc(title: string, width, height: int) {
	app: ^ns.Application
	{
		// Drain startup temporaries before entering AppKit's event loop, which
		// manages its own autorelease pools while processing events.
		ns.scoped_autoreleasepool()

		app = ns.Application.sharedApplication()
		assert(app != nil, "Could not create the macOS application")
		assert(app->setActivationPolicy(.Regular), "Could not activate the macOS application")

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
		// NSWindow releases itself on close by default.
		native_title := ns.String.alloc()->initWithOdinString(title)
		defer native_title->release()
		window->setTitle(native_title)
		window->center()
		window->makeKeyAndOrderFront(nil)
		app->activateIgnoringOtherApps(true)
	}

	app->run()
}

@(private)
terminate_after_last_window_closed :: proc(_: ^ns.Application) -> ns.BOOL {
	return true
}
