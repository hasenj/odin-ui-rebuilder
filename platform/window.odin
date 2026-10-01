package platform

import "../core/primitives"
import "../core/input"
import "core:strings"
import "core:fmt"

// Called on the main thread at a target rate of 60 fps. The returned slice must
// remain valid until the next callback; the platform consumes it immediately.
Frame_Proc :: #type proc(renderer: Renderer, elapsed: f64, size: [2]f32, user_data: rawptr) -> []primitives.Surface

// Main-thread application lifetime. run returns when the last window closes.
// Windows requested inside a frame are realized after that frame finishes.
Window :: struct {index, generation: u32}
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
	decorated, transparent, closing: bool,
	native: rawptr,
}

@(private)
windows: [dynamic]^Window_Record
@(private)
window_generation: u32
@(private)
initialized, running, servicing, updating: bool

init :: proc() {
	assert(!initialized, "Application already initialized")
	initialized = true
	application_init_impl()
}

shutdown :: proc() {
	assert(initialized && !running && !updating)
	for window in windows {
		if window != nil { window.closing = true }
	}
	service_windows()
	delete(windows)
	windows = nil
	application_shutdown_impl()
	initialized = false
}

create_window :: proc(title: string, width, height: int, frame: Frame_Proc = nil, user_data: rawptr = nil, frame_timing: Frame_Timing = .Disabled, input_state: ^input.State = nil, decorated: bool = true, transparent: bool = ODIN_OS == .Darwin, destroy: Destroy_Proc = nil) -> Window {
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
		input_state = input_state, decorated = decorated, transparent = transparent}
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

// Idempotent; invalid/stale handles do nothing. The current frame can finish.
request_close :: proc(window: Window) {
	if record := window_record(window); record != nil { record.closing = true }
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
