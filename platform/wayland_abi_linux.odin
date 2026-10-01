// Minimal bindings to the system Wayland client, EGL-window, and cursor libraries.
// The wire protocol is marshalled by libwayland-client, not reimplemented here.
package platform

WL_Interface :: struct {
	name: cstring,
	version: i32,
	method_count: i32,
	methods: [^]WL_Message,
	event_count: i32,
	events: [^]WL_Message,
}
WL_Message :: struct {name, signature: cstring, types: [^]^WL_Interface}
WL_Array :: struct {size, alloc: uintptr, data: rawptr}
WL_Argument :: struct #raw_union {i: i32, u: u32, o: rawptr, s: cstring}
WL_Cursor_Image :: struct {width, height, hotspot_x, hotspot_y, delay: u32}
WL_Cursor :: struct {image_count: u32, images: [^]^WL_Cursor_Image, name: cstring}

foreign import wayland_client "system:wayland-client"
foreign import wayland_egl "system:wayland-egl"
foreign import wayland_cursor "system:wayland-cursor"
foreign wayland_client {
	wl_display_get_fd :: proc(display: rawptr) -> i32 ---
	wl_display_prepare_read :: proc(display: rawptr) -> i32 ---
	wl_display_read_events :: proc(display: rawptr) -> i32 ---
	wl_display_cancel_read :: proc(display: rawptr) ---
	wl_display_connect :: proc(name: cstring) -> rawptr ---
	wl_display_disconnect :: proc(display: rawptr) ---
	wl_display_roundtrip :: proc(display: rawptr) -> i32 ---
	wl_display_dispatch :: proc(display: rawptr) -> i32 ---
	wl_display_dispatch_pending :: proc(display: rawptr) -> i32 ---
	wl_display_flush :: proc(display: rawptr) -> i32 ---
	wl_proxy_get_version :: proc(proxy: rawptr) -> u32 ---
	wl_proxy_destroy :: proc(proxy: rawptr) ---
	wl_proxy_add_listener :: proc(proxy, listener, data: rawptr) -> i32 ---
	wl_proxy_marshal_array_flags :: proc(proxy: rawptr, opcode: u32, iface: ^WL_Interface, version, flags: u32, args: [^]WL_Argument) -> rawptr ---
	wl_registry_interface, wl_compositor_interface, wl_surface_interface: WL_Interface
	wl_callback_interface, wl_seat_interface, wl_pointer_interface, wl_keyboard_interface: WL_Interface
	wl_output_interface, wl_shm_interface: WL_Interface
}
foreign wayland_egl {
	wl_egl_window_create :: proc(surface: rawptr, width, height: i32) -> rawptr ---
	wl_egl_window_resize :: proc(window: rawptr, width, height, dx, dy: i32) ---
	wl_egl_window_destroy :: proc(window: rawptr) ---
}
foreign wayland_cursor {
	wl_cursor_theme_load :: proc(name: cstring, size: i32, shm: rawptr) -> rawptr ---
	wl_cursor_theme_destroy :: proc(theme: rawptr) ---
	wl_cursor_theme_get_cursor :: proc(theme: rawptr, name: cstring) -> ^WL_Cursor ---
	wl_cursor_image_get_buffer :: proc(image: ^WL_Cursor_Image) -> rawptr ---
}

@(private)
wl_request :: proc(proxy: rawptr, opcode: u32, args: []WL_Argument = nil) {
	wl_proxy_marshal_array_flags(proxy, opcode, nil, wl_proxy_get_version(proxy), 0, raw_data(args))
}

@(private)
wl_construct :: proc(proxy: rawptr, opcode: u32, iface: ^WL_Interface, args: []WL_Argument, version: u32 = 1) -> rawptr {
	result := wl_proxy_marshal_array_flags(proxy, opcode, iface, version, 0, raw_data(args))
	linux_require(result != nil, "Wayland object creation failed")
	return result
}

@(private)
wl_release :: proc(proxy: rawptr, opcode: u32) {
	if proxy != nil {
		wl_proxy_marshal_array_flags(proxy, opcode, nil, wl_proxy_get_version(proxy), 1, nil)
	}
}

@(private)
wl_listen :: proc(proxy, listener, data: rawptr) {
	linux_require(wl_proxy_add_listener(proxy, listener, data) == 0, "Wayland listener registration failed")
}

// Unlike a build-time-disableable assertion, these checks always perform the
// native operation and report failures in optimized/release builds too.
@(private)
linux_require :: proc(ok: bool, message: string) {
	if !ok {
		panic(message)
	}
}
