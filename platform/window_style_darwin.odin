package platform

import "base:intrinsics"
import ns "core:sys/darwin/Foundation"
import mtk "vendor:darwin/MetalKit"

@(private)
create_macos_window :: proc(width, height: int, decorated, transparent: bool, panel: bool = false) -> ^ns.Window {
	name: cstring = "OdinUIRebuilderPanel" if panel else "OdinUIRebuilderWindow"
	cls := ns.objc_lookUpClass(name)
	if cls == nil {
		base := intrinsics.objc_find_class("NSPanel") if panel else intrinsics.objc_find_class("NSWindow")
		cls = ns.objc_allocateClassPair(base, name, 0)
		assert(cls != nil)
		// Borderless NSWindows otherwise refuse keyboard/main-window status.
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("canBecomeKeyWindow"), auto_cast native_yes, "B@:"))
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("canBecomeMainWindow"), auto_cast (native_no if panel else native_yes), "B@:"))
		ns.objc_registerClassPair(cls)
	}
	style := ns.WindowStyleMask{.Closable, .Miniaturizable, .Resizable}
	if decorated { style += {.Titled} }
	window := intrinsics.objc_send(^ns.Window, cast(^ns.Object)cls, "alloc")->initWithContentRect(
		{size = {ns.Float(width), ns.Float(height)}}, style, .Buffered, false)
	assert(window != nil)
	if panel {
		intrinsics.objc_send(nil, window, "setTabbingMode:", ns.WindowTabbingMode.Disallowed)
		intrinsics.objc_send(nil, window, "setFloatingPanel:", ns.BOOL(true))
		window->setLevel(.Floating)
		// Tool palettes stay above our workspace, but disappear when another
		// application becomes active instead of covering its windows.
		intrinsics.objc_send(nil, window, "setHidesOnDeactivate:", ns.BOOL(true))
	}
	window->setOpaque(ns.BOOL(!transparent))
	if transparent {
		window->setBackgroundColor(ns.Color.colorWithSRGBRed(0, 0, 0, 0))
		// Avoid a native rectangular shadow surrounding application-painted shapes.
		intrinsics.objc_send(nil, window, "setHasShadow:", ns.BOOL(false))
	}
	// Until custom drag regions exist, a borderless window moves by its background.
	window->setMovableByWindowBackground(ns.BOOL(!decorated))
	return window
}

@(private)
allocate_metal_view :: proc() -> ^mtk.View {
	cls := ns.objc_lookUpClass("OdinUIRebuilderMetalView")
	if cls == nil {
		cls = ns.objc_allocateClassPair(intrinsics.objc_find_class("MTKView"), "OdinUIRebuilderMetalView", 0)
		assert(cls != nil)
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("isOpaque"), auto_cast metal_view_is_opaque, "B@:"))
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("mouseDownCanMoveWindow"), auto_cast native_yes, "B@:"))
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("scrollWheel:"), auto_cast metal_view_scroll_wheel, "v@:@"))
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("acceptsFirstResponder"), auto_cast native_yes, "B@:"))
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("keyDown:"), auto_cast metal_view_key_down, "v@:@"))
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("keyUp:"), auto_cast metal_view_key_up, "v@:@"))
		assert(ns.class_addMethod(cls, intrinsics.objc_find_selector("flagsChanged:"), auto_cast metal_view_flags_changed, "v@:@"))
		ns.objc_registerClassPair(cls)
	}
	return intrinsics.objc_send(^mtk.View, cast(^ns.Object)cls, "alloc")
}

@(private)
configure_metal_transparency :: proc(view: ^mtk.View, transparent: bool) {
	layer := intrinsics.objc_send(^ns.Layer, view, "layer")
	assert(layer != nil, "Metal view must have a backing layer")
	intrinsics.objc_send(nil, layer, "setOpaque:", ns.BOOL(!transparent))
	if transparent {
		view->setClearColor({0, 0, 0, 0})
	} else {
		view->setClearColor({0.035, 0.045, 0.065, 1})
	}
}

@(private)
native_yes :: proc "c" (_: ns.id, _: ns.SEL) -> ns.BOOL {
	return true
}

@(private)
metal_view_is_opaque :: proc "c" (self: ns.id, _: ns.SEL) -> ns.BOOL {
	layer := intrinsics.objc_send(^ns.Layer, cast(^mtk.View)self, "layer")
	return intrinsics.objc_send(ns.BOOL, layer, "isOpaque")
}

// Borderless windows have no close button; provide the standard Command-Q path.
@(private)
install_application_menu :: proc(app: ^ns.Application) {
	menu := ns.Menu.alloc()->init()
	defer menu->release()
	item := ns.MenuItem.alloc()->init()
	defer item->release()
	submenu := ns.Menu.alloc()->init()
	defer submenu->release()
	title := ns.String.alloc()->initWithOdinString("Quit")
	defer title->release()
	key := ns.String.alloc()->initWithOdinString("q")
	defer key->release()
	quit := submenu->addItemWithTitle(title, intrinsics.objc_find_selector("terminate:"), key)
	quit->setTarget(app)
	item->setSubmenu(submenu)
	menu->addItem(item)
	app->setMainMenu(menu)
}

@(private)
native_no :: proc "c" (_: ns.id, _: ns.SEL) -> ns.BOOL { return false }
