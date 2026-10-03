package platform

import "../core/primitives"
import "../core/input"
import "core:strings"
import "core:fmt"
import "core:time"

// Called once per application cycle, main first then panels in creation order.
// Surfaces must remain valid until the next cycle; presentation follows all builders.
Frame_Proc :: #type proc(renderer: Renderer, elapsed: f64, size: [2]f32, user_data: rawptr) -> []primitives.Surface

// The main window owns application lifetime. Panels never keep it alive.
Window :: struct {index, generation: u32}
Panel :: Window
Destroy_Proc :: #type proc(user_data: rawptr)

@(private)
Window_Record :: struct {
	handle: Window,
	title: string,
	width, height: int,
	frame: Frame_Proc,
	user_data: rawptr,
	destroy: Destroy_Proc,
	frame_timing: Frame_Timing,
	input_state: ^input.State,
	decorated, transparent, closing, panel: bool,
	drag_region: primitives.Clip,
	renderer: Renderer,
	size: [2]f32,
	surfaces: []primitives.Surface,
	profiler: Frame_Profiler,
	update_ms, wall_ms: f64,
	render_time: Render_Timing,
	native: rawptr,
}

@(private)
windows: [dynamic]^Window_Record
@(private)
window_generation: u32
@(private)
initialized, running, servicing, updating: bool
@(private)
main_window: Window
@(private)
cycle_windows: [dynamic]^Window_Record
@(private)
application_start: time.Tick

init :: proc() {
	assert(!initialized, "Application already initialized")
	initialized = true
	main_window = {}
	application_start = time.tick_now()
	application_init_impl()
}

shutdown :: proc() {
	assert(initialized && !running && !updating)
	for window in windows {
		if window != nil { window.closing = true }
	}
	service_windows()
	delete(cycle_windows)
	cycle_windows = nil
	delete(windows)
	windows = nil
	application_shutdown_impl()
	initialized = false
}

create_window :: proc(title: string, width, height: int, frame: Frame_Proc = nil, user_data: rawptr = nil, frame_timing: Frame_Timing = .Disabled, input_state: ^input.State = nil, decorated: bool = true, transparent: bool = ODIN_OS == .Darwin, destroy: Destroy_Proc = nil) -> Window {
	assert(main_window == (Window{}), "Create one main window per application; use create_panel for auxiliary UI")
	main_window = create_window_record(title, width, height, frame, user_data, frame_timing, input_state, decorated, transparent, destroy, false)
	return main_window
}

create_panel :: proc(title: string, width, height: int, frame: Frame_Proc = nil, user_data: rawptr = nil, frame_timing: Frame_Timing = .Disabled, input_state: ^input.State = nil, decorated: bool = false, transparent: bool = ODIN_OS == .Darwin, destroy: Destroy_Proc = nil) -> Panel {
	assert(initialized)
	if !window_alive(main_window) { return {} }
	return create_window_record(title, width, height, frame, user_data, frame_timing, input_state, decorated, transparent, destroy, true)
}

// A panel-only close cannot accidentally close the application's main window.
close_panel :: proc(panel: Panel) {
	if record := window_record(panel); record != nil && record.panel { request_close(panel) }
}

@(private)
create_window_record :: proc(title: string, width, height: int, frame: Frame_Proc, user_data: rawptr, frame_timing: Frame_Timing, input_state: ^input.State, decorated, transparent: bool, destroy: Destroy_Proc, panel: bool) -> Window {
	assert(initialized && width > 0 && height > 0)
	index := len(windows)
	for item, i in windows {
		if item == nil { index = i; break }
	}
	// Do not reuse generations, including across shutdown/init sessions.
	assert(window_generation < max(u32), "Window generations exhausted")
	window_generation += 1
	handle := Window{u32(index + 1), window_generation}
	record := new(Window_Record)
	record^ = {handle = handle, title = strings.clone(title), width = width, height = height,
		frame = frame, user_data = user_data, destroy = destroy, frame_timing = frame_timing,
		input_state = input_state, decorated = decorated, transparent = transparent, panel = panel,
		profiler = {mode = frame_timing, window = handle}}
	if index == len(windows) { append(&windows, record) } else { windows[index] = record }
	return handle
}

@(private)
window_record :: proc(handle: Window) -> ^Window_Record {
	if handle.index == 0 || int(handle.index) > len(windows) { return nil }
	record := windows[handle.index - 1]
	return record if record != nil && record.handle == handle else nil
}

window_alive :: proc(window: Window) -> bool {
	record := window_record(window)
	return record != nil && !record.closing
}

// Opt into a custom drag area, in content-local logical coordinates. An empty
// region disables background dragging. Currently consumed by macOS; Wayland
// compositors can still move borderless windows using their own bindings.
set_window_drag_region :: proc(window: Window, position, size: [2]f32) {
	if record := window_record(window); record != nil {
		record.drag_region = {true, position, position + [2]f32{max(0, size.x), max(0, size.y)}}
	}
}

// Idempotent; stale handles do nothing. The entire current cycle finishes.
// Closing the main window closes all panels, including pending creations.
request_close :: proc(window: Window) {
	if record := window_record(window); record != nil {
		record.closing = true
		if window == main_window {
			for item in windows { if item != nil { item.closing = true } }
		}
	}
}

run :: proc() {
	assert(initialized && !running && !updating)
	running = true
	defer { running = false }
	service_windows()
	if window_count() > 0 { application_run_impl() }
}

@(private)
window_count :: proc() -> int {
	count := 0
	for window in windows { if window != nil { count += 1 } }
	return count
}

@(private)
service_windows :: proc() {
	if servicing || updating { return }
	servicing = true
	defer { servicing = false }
	// Access by index: creation during a native callback may grow the registry.
	count := len(windows)
	for i in 0..<count {
		window := windows[i]
		if window == nil { continue }
		if window.closing {
			if window.native != nil { destroy_window_impl(window) }
			windows[i] = nil
			if window.destroy != nil { window.destroy(window.user_data) }
			delete(window.title)
			free(window)
		} else if window.native == nil {
			if window.frame_timing != .Disabled {
				fmt.printf("[window %d:%d] %s — frame wall = update + submit + measured waits + overhead; GPU execution and logging excluded.\n", window.handle.index, window.handle.generation, window.title)
			}
			create_window_impl(window)
		}
	}
}

// Single-window convenience; the same lifecycle and cleanup as the explicit API.
open_window :: proc(title: string, width, height: int, frame: Frame_Proc = nil, user_data: rawptr = nil, frame_timing: Frame_Timing = .Disabled, input_state: ^input.State = nil, decorated: bool = true, transparent: bool = ODIN_OS == .Darwin) {
	init()
	defer shutdown()
	create_window(title, width, height, frame, user_data, frame_timing, input_state, decorated, transparent)
	run()
}

// Freeze membership and all input/size snapshots before running any user code.
// Native presentation callbacks never independently run a UI builder.
@(private)
application_cycle :: proc() {
	if updating || servicing || !running { return }
	service_windows()
	if !window_alive(main_window) { return }
	updating = true
	defer { updating = false; service_windows() }
	defer free_all(context.temp_allocator)
	clear(&cycle_windows)
	for record in windows {
		if record != nil && !record.closing && record.native != nil { append(&cycle_windows, record) }
	}
	// Slot reuse must not change update order. The main window was created first.
	for i in 1..<len(cycle_windows) {
		j := i
		for j > 0 && cycle_windows[j-1].handle.generation > cycle_windows[j].handle.generation {
			cycle_windows[j-1], cycle_windows[j] = cycle_windows[j], cycle_windows[j-1]
			j -= 1
		}
	}
	start := time.tick_now()
	elapsed := time.duration_seconds(time.tick_diff(application_start, start))
	for record in cycle_windows {
		tick := time.tick_now()
		snapshot_window_impl(record)
		record.wall_ms = time.duration_milliseconds(time.tick_since(tick))
		record.render_time = {}
	}
	for record in cycle_windows {
		tick := time.tick_now()
		prepare_window_impl(record)
		update_start := time.tick_now()
		if record.frame != nil {
			record.surfaces = record.frame(record.renderer, elapsed, record.size, record.user_data)
		}
		record.update_ms = time.duration_milliseconds(time.tick_since(update_start))
		record.wall_ms += time.duration_milliseconds(time.tick_since(tick))
	}
	for record in cycle_windows {
		tick := time.tick_now()
		present_window_impl(record)
		record.wall_ms += time.duration_milliseconds(time.tick_since(tick))
		if record.frame_timing != .Disabled {
			record_frame_timing(&record.profiler, start, record.update_ms, record.render_time, len(record.surfaces), record.wall_ms)
		}
	}
}
