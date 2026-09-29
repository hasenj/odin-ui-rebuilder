package platform

// Listener layouts follow the exact negotiated protocol versions: compositor 3/4,
// seat/pointer 5, output 2, and xdg-shell/decoration 1. Callbacks restore Odin's
// context because Wayland calls them through the C ABI.

@(private)
registry_global :: proc "c" (data, registry: rawptr, name: u32, interface: cstring, version: u32) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	iface: ^WL_Interface
	bind_version: u32
	switch string(interface) {
	case "wl_compositor":
		if version >= 3 && w.compositor == nil {
			iface = &wl_compositor_interface
			bind_version = min(version, 4)
		}
	case "xdg_wm_base":
		if w.shell == nil {
			iface = &xdg_wm_base_interface
			bind_version = 1
		}
	case "wl_seat":
		if version >= 5 && w.seat == nil {
			iface = &wl_seat_interface
			bind_version = 5
		}
	case "wl_shm":
		if w.shm == nil {
			iface = &wl_shm_interface
			bind_version = 1
		}
	case "wl_output":
		if version >= 2 {
			iface = &wl_output_interface
			bind_version = 2
		}
	case "zxdg_decoration_manager_v1":
		if w.decoration_manager == nil {
			iface = &zxdg_decoration_manager_v1_interface
			bind_version = 1
		}
	}
	if iface == nil {
		return
	}
	proxy := wl_construct(registry, 0, iface, []WL_Argument{{u = name}, {s = interface}, {u = bind_version}, {o = nil}}, bind_version)
	switch string(interface) {
	case "wl_compositor":
		w.compositor = proxy
	case "xdg_wm_base":
		w.shell = proxy
		wl_listen(proxy, &shell_listener, w)
	case "wl_seat":
		w.seat = proxy
		w.seat_name = name
		wl_listen(proxy, &seat_listener, w)
	case "wl_shm":
		w.shm = proxy
	case "zxdg_decoration_manager_v1":
		w.decoration_manager = proxy
	case "wl_output":
		append(&w.outputs, Wayland_Output{proxy = proxy, name = name, scale = 1})
		wl_listen(proxy, &output_listener, w)
	}
}

@(private)
registry_remove :: proc "c" (data, _: rawptr, name: u32) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	if name == w.seat_name && w.seat != nil {
		wl_release(w.pointer, 1)
		wl_release(w.seat, 3)
		w.pointer = nil
		w.seat = nil
		w.pointer_focused = false
		w.input = {}
		w.scroll_group = {}
	}
	for output, i in w.outputs {
		if output.name == name {
			wl_proxy_destroy(output.proxy)
			w.outputs[i] = w.outputs[len(w.outputs) - 1]
			resize(&w.outputs, len(w.outputs) - 1)
			update_window_scale(w)
			break
		}
	}
}

@(private)
shell_ping :: proc "c" (data, shell: rawptr, serial: u32) {
	context = (cast(^Wayland_Window)data).odin_context
	wl_request(shell, 3, []WL_Argument{{u = serial}})
}

@(private)
shell_configure :: proc "c" (data, shell_surface: rawptr, serial: u32) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	wl_request(shell_surface, 4, []WL_Argument{{u = serial}})
	if w.pending_width > 0 {
		w.width = w.pending_width
	}
	if w.pending_height > 0 {
		w.height = w.pending_height
	}
	w.configured = true
	update_window_scale(w)
}

@(private)
toplevel_configure :: proc "c" (data, _: rawptr, width, height: i32, _: ^WL_Array) {
	w := cast(^Wayland_Window)data
	w.pending_width = width
	w.pending_height = height
}

@(private)
toplevel_close :: proc "c" (data, _: rawptr) {
	w := cast(^Wayland_Window)data
	w.running = false
}

@(private)
decoration_configure :: proc "c" (_: rawptr, _: rawptr, _: u32) {}

@(private)
frame_done :: proc "c" (data, callback: rawptr, _: u32) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	wl_proxy_destroy(callback)
	w.frame_callback = nil
	w.frame_ready = true
}

@(private)
seat_capabilities :: proc "c" (data, seat: rawptr, capabilities: u32) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	if capabilities & 1 != 0 && w.pointer == nil {
		w.pointer = wl_construct(seat, 0, &wl_pointer_interface, []WL_Argument{{o = nil}}, 5)
		wl_listen(w.pointer, &pointer_listener, w)
	} else if capabilities & 1 == 0 && w.pointer != nil {
		wl_release(w.pointer, 1)
		w.pointer = nil
		w.pointer_focused = false
		w.input = {}
		w.scroll_group = {}
	}
}

@(private)
seat_name :: proc "c" (_: rawptr, _: rawptr, _: cstring) {}

@(private)
pointer_enter :: proc "c" (data, _: rawptr, serial: u32, surface: rawptr, x, y: i32) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	if surface != w.surface {
		return
	}
	w.pointer_serial = serial
	w.pointer_focused = true
	w.input.mouse_position = {f32(x) / 256, f32(y) / 256}
	w.input.mouse_inside = true
	show_pointer(w)
}

@(private)
pointer_leave :: proc "c" (data, _: rawptr, _: u32, _: rawptr) {
	w := cast(^Wayland_Window)data
	w.pointer_focused = false
	w.input.mouse_inside = false
	w.input.mouse_buttons = {}
	w.input.scroll_delta = {}
	w.scroll_group = {}
}

@(private)
pointer_motion :: proc "c" (data, _: rawptr, _: u32, x, y: i32) {
	w := cast(^Wayland_Window)data
	w.input.mouse_position = {f32(x) / 256, f32(y) / 256}
	w.input.mouse_inside = x >= 0 && y >= 0 && f32(x) / 256 < f32(w.width) && f32(y) / 256 < f32(w.height)
}

@(private)
pointer_button :: proc "c" (data, _: rawptr, _: u32, _: u32, button, state: u32) {
	w := cast(^Wayland_Window)data
	switch button {
	case 0x110:
		// Linux BTN_LEFT.
		if state == 1 {
			w.input.mouse_buttons += {.Left}
		} else {
			w.input.mouse_buttons -= {.Left}
		}
	case 0x111:
		// Linux BTN_RIGHT.
		if state == 1 {
			w.input.mouse_buttons += {.Right}
		} else {
			w.input.mouse_buttons -= {.Right}
		}
	}
}

@(private)
pointer_axis :: proc "c" (data, _: rawptr, _: u32, axis: u32, value: i32) {
	w := cast(^Wayland_Window)data
	if !w.pointer_focused {
		return
	}
	// wl_pointer axis values already use surface-local logical coordinates,
	// with positive values moving towards the right/bottom.
	switch axis {
	case 0: w.scroll_group.y += f32(value) / 256
	case 1: w.scroll_group.x += f32(value) / 256
	}
}
@(private)
pointer_frame :: proc "c" (data, _: rawptr) {
	w := cast(^Wayland_Window)data
	w.input.scroll_delta += w.scroll_group
	w.scroll_group = {}
}
@(private)
pointer_axis_source :: proc "c" (_: rawptr, _: rawptr, _: u32) {}
@(private)
pointer_axis_stop :: proc "c" (_: rawptr, _: rawptr, _: u32, _: u32) {}
// Discrete steps describe the same movement as axis; do not count it twice.
@(private)
pointer_axis_discrete :: proc "c" (_: rawptr, _: rawptr, _: u32, _: i32) {}

@(private)
output_geometry :: proc "c" (_: rawptr, _: rawptr, _: i32, _: i32, _: i32, _: i32, _: i32, _: cstring, _: cstring, _: i32) {}
@(private)
output_mode :: proc "c" (_: rawptr, _: rawptr, _: u32, _: i32, _: i32, _: i32) {}
@(private)
output_done :: proc "c" (_: rawptr, _: rawptr) {}

@(private)
output_scale :: proc "c" (data, proxy: rawptr, scale: i32) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	for &output in w.outputs {
		if output.proxy == proxy {
			output.scale = max(scale, 1)
		}
	}
	update_window_scale(w)
}

@(private)
surface_enter :: proc "c" (data, _: rawptr, proxy: rawptr) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	for &output in w.outputs {
		if output.proxy == proxy {
			output.entered = true
		}
	}
	update_window_scale(w)
}

@(private)
surface_leave :: proc "c" (data, _: rawptr, proxy: rawptr) {
	w := cast(^Wayland_Window)data
	context = w.odin_context
	for &output in w.outputs {
		if output.proxy == proxy {
			output.entered = false
		}
	}
	update_window_scale(w)
}

registry_listener := struct {global: type_of(registry_global), remove: type_of(registry_remove)}{registry_global, registry_remove}
shell_listener := struct {ping: type_of(shell_ping)}{shell_ping}
shell_surface_listener := struct {configure: type_of(shell_configure)}{shell_configure}
toplevel_listener := struct {configure: type_of(toplevel_configure), close: type_of(toplevel_close)}{toplevel_configure, toplevel_close}
decoration_listener := struct {configure: type_of(decoration_configure)}{decoration_configure}
frame_listener := struct {done: type_of(frame_done)}{frame_done}
seat_listener := struct {capabilities: type_of(seat_capabilities), name: type_of(seat_name)}{seat_capabilities, seat_name}
surface_listener := struct {enter: type_of(surface_enter), leave: type_of(surface_leave)}{surface_enter, surface_leave}
output_listener := struct {geometry: type_of(output_geometry), mode: type_of(output_mode), done: type_of(output_done), scale: type_of(output_scale)}{output_geometry, output_mode, output_done, output_scale}
pointer_listener := struct {
	enter: type_of(pointer_enter), leave: type_of(pointer_leave), motion: type_of(pointer_motion), button: type_of(pointer_button), axis: type_of(pointer_axis),
	frame: type_of(pointer_frame), axis_source: type_of(pointer_axis_source), axis_stop: type_of(pointer_axis_stop), axis_discrete: type_of(pointer_axis_discrete),
}{pointer_enter, pointer_leave, pointer_motion, pointer_button, pointer_axis, pointer_frame, pointer_axis_source, pointer_axis_stop, pointer_axis_discrete}
