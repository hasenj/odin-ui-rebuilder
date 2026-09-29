package platform

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"
import egl "vendor:egl"
import inputs "../core/input"
import "../core/primitives"

@(private)
Wayland_Output :: struct {proxy: rawptr, name: u32, scale: i32, entered: bool}

@(private)
Wayland_Window :: struct {
	odin_context: runtime.Context,
	display, registry, compositor, shell, surface, shell_surface, toplevel: rawptr,
	seat, pointer, keyboard_proxy, shm, decoration_manager, decoration: rawptr,
	cursor_surface, cursor_theme, frame_callback, native_window: rawptr,
	egl_context: egl.Context,
	renderer: GL_Renderer,
	outputs: [dynamic]Wayland_Output,
	input: inputs.State,
	scroll_group: [2]f32,
	keyboard: Keyboard_Input,
	xkb_context, xkb_keymap, xkb_state: rawptr,
	held_keys: map[u32]inputs.Key,
	keyboard_focused, repeat_active: bool,
	repeat_code: u32,
	repeat_rate, repeat_delay: i32,
	repeat_at: time.Tick,
	width, height, pending_width, pending_height, scale: i32,
	pointer_serial: u32,
	seat_name: u32,
	pointer_focused: bool,
	running, configured, frame_ready: bool,
}

@(private)
open_window_impl :: proc(title: string, width, height: int, frame: Frame_Proc, user_data: rawptr, frame_timing: Frame_Timing, input_state: ^inputs.State, decorated, transparent: bool) {
	wayland_init_protocols()
	window := Wayland_Window{
		odin_context = context, width = i32(width), height = i32(height),
		scale = 1, running = true, frame_ready = true,
		outputs = make([dynamic]Wayland_Output),
		renderer = GL_Renderer{transparent = transparent},
	}
	window.display = wl_display_connect(nil)
	linux_require(window.display != nil, "Could not connect to Wayland. Run inside a Wayland desktop session (check WAYLAND_DISPLAY and XDG_RUNTIME_DIR).")
	defer wayland_destroy(&window)
	window.registry = wl_construct(window.display, 1, &wl_registry_interface, []WL_Argument{{o = nil}})
	wl_listen(window.registry, &registry_listener, &window)
	linux_require(wl_display_roundtrip(window.display) >= 0, "Wayland registry roundtrip failed")
	linux_require(window.compositor != nil && window.shell != nil, "Compositor requires wl_compositor v3+ and xdg_wm_base")
	linux_require(wl_display_roundtrip(window.display) >= 0, "Wayland initial state roundtrip failed")
	window.surface = wl_construct(window.compositor, 0, &wl_surface_interface, []WL_Argument{{o = nil}}, wl_proxy_get_version(window.compositor))
	wl_listen(window.surface, &surface_listener, &window)
	// Keep the default empty opaque region: the compositor must honor buffer alpha.
	window.shell_surface = wl_construct(window.shell, 2, &xdg_surface_interface, []WL_Argument{{o = nil}, {o = window.surface}})
	wl_listen(window.shell_surface, &shell_surface_listener, &window)
	window.toplevel = wl_construct(window.shell_surface, 1, &xdg_toplevel_interface, []WL_Argument{{o = nil}})
	wl_listen(window.toplevel, &toplevel_listener, &window)
	native_title := strings.clone_to_cstring(title)
	defer delete(native_title)
	wl_request(window.toplevel, 2, []WL_Argument{{s = native_title}})
	wl_request(window.toplevel, 3, []WL_Argument{{s = "odin-ui-rebuilder"}})
	if window.decoration_manager != nil {
		window.decoration = wl_construct(window.decoration_manager, 1, &zxdg_toplevel_decoration_v1_interface, []WL_Argument{{o = nil}, {o = window.toplevel}})
		wl_listen(window.decoration, &decoration_listener, &window)
		// xdg-decoration modes: client-side = 1, server-side = 2.
		// This is a preference; the compositor may enforce its own decoration mode.
		wl_request(window.decoration, 1, []WL_Argument{{u = 2 if decorated else 1}})
	}
	// xdg-shell requires an initial empty commit and configure acknowledgement
	// before attaching the first rendered buffer.
	wl_request(window.surface, 6)
	for window.running && !window.configured {
		linux_require(wl_display_dispatch(window.display) >= 0, "Wayland initial configure failed")
	}
	if !window.running {
		return
	}
	window.native_window = wl_egl_window_create(window.surface, window.width * window.scale, window.height * window.scale)
	linux_require(window.native_window != nil, "Could not create the Wayland EGL window")
	window.renderer.display = egl.GetPlatformDisplay(.WAYLAND_KHR, window.display, nil)
	linux_require(bool(egl.Initialize(window.renderer.display, nil, nil)), "Could not initialize EGL on Wayland")
	config := gles_config(window.renderer.display, egl.WINDOW_BIT)
	window.egl_context = gles_context(window.renderer.display, config)
	window.renderer.surface = egl.CreateWindowSurface(window.renderer.display, config, egl.NativeWindowType(window.native_window), nil)
	linux_require(window.renderer.surface != nil, "Could not create EGL window surface")
	linux_require(bool(egl.MakeCurrent(window.renderer.display, window.renderer.surface, window.renderer.surface, window.egl_context)), "Could not make EGL context current")
	linux_require(bool(egl.SwapInterval(window.renderer.display, 1)), "Could not enable EGL swap pacing")
	gl_init(&window.renderer)
	update_window_scale(&window)
	if frame_timing != .Disabled {
		fmt.println("[frame timing] Wall-clock durations; submit excludes waits (EGL swap/presentation calls, including API overhead). GPU execution is not measured separately. Logging is excluded; interval measures callback spacing.")
	}
	profiler := Frame_Profiler{mode = frame_timing}
	start := time.tick_now()
	previous_frame: time.Tick
	for window.running {
		if wl_display_dispatch_pending(window.display) < 0 {
			break
		}
		if !window.running {
			break
		}
		if window.frame_ready {
			// Cap at 60 updates/s; frame callbacks also throttle us to the
			// compositor and stop rendering while the window is hidden.
			if previous_frame != (time.Tick{}) {
				remaining := time.Second / 60 - time.tick_since(previous_frame)
				if remaining > 0 {
					time.sleep(remaining)
				}
			}
			previous_frame = time.tick_now()
			wayland_frame(&window, frame, user_data, input_state, start, &profiler)
		} else if wl_display_dispatch(window.display) < 0 {
			break
		}
	}
}

@(private)
wayland_frame :: proc(window: ^Wayland_Window, frame: Frame_Proc, user_data: rawptr, input_state: ^inputs.State, start: time.Tick, profiler: ^Frame_Profiler) {
	profiling := profiler.mode != .Disabled
	frame_start, update_start: time.Tick
	update_ms: f64
	render_time: Render_Timing
	surfaces: []primitives.Surface
	if profiling {
		frame_start = time.tick_now()
	}
	defer {
		if profiling {
			record_frame_timing(profiler, frame_start, update_ms, render_time, len(surfaces))
		}
	}
	defer free_all(context.temp_allocator)
	position := window.input.mouse_position
	window.input.mouse_inside = window.pointer_focused && position.x >= 0 && position.y >= 0 && position.x < f32(window.width) && position.y < f32(window.height)
	snapshot := take_wayland_input(window)
	if input_state != nil {
		input_state^ = snapshot
	}
	window.frame_ready = false
	window.frame_callback = wl_construct(window.surface, 3, &wl_callback_interface, []WL_Argument{{o = nil}})
	wl_listen(window.frame_callback, &frame_listener, window)
	if profiling {
		update_start = time.tick_now()
	}
	size := [2]f32{f32(window.width), f32(window.height)}
	if frame != nil {
		surfaces = frame(Renderer(&window.renderer), time.duration_seconds(time.tick_since(start)), size, user_data)
	}
	if profiling {
		update_ms = time.duration_milliseconds(time.tick_since(update_start))
	}
	render(Renderer(&window.renderer), surfaces, size, &render_time if profiling else nil)
}

@(private)
take_wayland_input :: proc(window: ^Wayland_Window) -> inputs.State {
	wayland_repeat(window)
	sample_keyboard(&window.keyboard, &window.input)
	result := window.input
	window.input.scroll_delta = {}
	return result
}

@(private)
wayland_destroy :: proc(window: ^Wayland_Window) {
	destroy_wayland_keyboard(window)
	if window.renderer.program != 0 {
		gl_destroy(&window.renderer)
	}
	if window.renderer.display != nil {
		egl.MakeCurrent(window.renderer.display, nil, nil, nil)
		if window.renderer.surface != nil {
			egl.DestroySurface(window.renderer.display, window.renderer.surface)
		}
		if window.egl_context != nil {
			egl.DestroyContext(window.renderer.display, window.egl_context)
		}
		egl.Terminate(window.renderer.display)
	}
	if window.native_window != nil {
		wl_egl_window_destroy(window.native_window)
	}
	if window.frame_callback != nil {
		wl_proxy_destroy(window.frame_callback)
	}
	if window.cursor_theme != nil {
		wl_cursor_theme_destroy(window.cursor_theme)
	}
	wl_release(window.cursor_surface, 0)
	wl_release(window.pointer, 1)
	wl_release(window.keyboard_proxy, 0)
	wl_release(window.decoration, 0)
	wl_release(window.toplevel, 0)
	wl_release(window.shell_surface, 0)
	wl_release(window.surface, 0)
	wl_release(window.decoration_manager, 0)
	wl_release(window.shell, 0)
	for output in window.outputs {
		wl_proxy_destroy(output.proxy)
	}
	delete(window.outputs)
	for proxy in ([]rawptr{window.seat, window.shm, window.compositor, window.registry}) {
		if proxy != nil {
			wl_proxy_destroy(proxy)
		}
	}
	wl_display_flush(window.display)
	wl_display_disconnect(window.display)
}

@(private)
update_window_scale :: proc(window: ^Wayland_Window) {
	scale: i32 = 1
	for output in window.outputs {
		if output.entered {
			scale = max(scale, output.scale)
		}
	}
	window.scale = scale
	if window.surface != nil {
		wl_request(window.surface, 8, []WL_Argument{{i = scale}})
	}
	window.renderer.pixel_size = {window.width * scale, window.height * scale}
	window.renderer.logical_scale = f32(scale)
	if window.native_window != nil {
		wl_egl_window_resize(window.native_window, window.renderer.pixel_size.x, window.renderer.pixel_size.y, 0, 0)
	}
}

@(private)
show_pointer :: proc(window: ^Wayland_Window) {
	if window.shm == nil || window.pointer == nil || window.compositor == nil {
		return
	}
	if window.cursor_theme == nil {
		window.cursor_theme = wl_cursor_theme_load(nil, 24, window.shm)
	}
	if window.cursor_theme == nil {
		return
	}
	cursor := wl_cursor_theme_get_cursor(window.cursor_theme, "left_ptr")
	if cursor == nil || cursor.image_count == 0 {
		return
	}
	if window.cursor_surface == nil {
		window.cursor_surface = wl_construct(window.compositor, 0, &wl_surface_interface, []WL_Argument{{o = nil}}, wl_proxy_get_version(window.compositor))
	}
	image := cursor.images[0]
	buffer := wl_cursor_image_get_buffer(image)
	wl_request(window.pointer, 0, []WL_Argument{{u = window.pointer_serial}, {o = window.cursor_surface}, {i = i32(image.hotspot_x)}, {i = i32(image.hotspot_y)}})
	wl_request(window.cursor_surface, 1, []WL_Argument{{o = buffer}, {i = 0}, {i = 0}})
	wl_request(window.cursor_surface, 2, []WL_Argument{{i = 0}, {i = 0}, {i = i32(image.width)}, {i = i32(image.height)}})
	wl_request(window.cursor_surface, 6)
}
