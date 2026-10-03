// Worker-owned filesystem IO, change polling and CPU image decoding. No UI or GPU.
package files

import "base:runtime"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:slice"
import "core:fmt"
import "core:sync"
import "core:thread"
import "core:time"
import "../images"

State :: enum {None, Reading, Done} // Done includes failures; inspect Result.error.
Kind :: enum {Directory, Image}
Entry :: struct {info: os.File_Info, directory: bool, sort_name: string}
Result :: struct {
	path, error: string,
	entries: [dynamic]Entry,
	folders: int,
	pixels: []u8,
	size: [2]int,
	revision: u64,
}
Task :: struct {
	path: string,
	kind: Kind,
	watch, pending, cancelled: bool,
	state: State,
	extent: int,
	revision: u64,
	ready: bool,
	result: Result,
	stamp: Stamp,
	checked: time.Tick,
}
Service :: struct {
	mutex: sync.Mutex,
	wake: sync.Cond,
	worker: ^thread.Thread,
	stopping: bool,
	tasks: [dynamic]^Task,
	garbage: [dynamic]Result,
	cursor: int,
}
@(private) Stamp :: struct {exists: bool, size: i64, modified: time.Time, inode: u128, device: u64, mode: os.Permissions}
POLL_INTERVAL :: 250 * time.Millisecond

// Stable service address required until destroy. Shared storage always uses the
// thread-safe heap, not the caller's frame arena or tracking allocator.
create :: proc() -> ^Service {
	context.allocator = runtime.heap_allocator()
	s := new(Service)
	s.worker = thread.create_and_start_with_data(s, worker_main, name = "file loader")
	assert(s.worker != nil, "Could not start file worker")
	return s
}

request :: proc(s: ^Service, path: string, kind: Kind, watch: bool = true, max_extent: int = 0) -> ^Task {
	context.allocator = runtime.heap_allocator()
	task := new(Task)
	task^ = {path = strings.clone(path), kind = kind, watch = watch, pending = true, state = .Reading, extent = max(0, max_extent)}
	sync.mutex_lock(&s.mutex)
	append(&s.tasks, task)
	sync.cond_signal(&s.wake)
	sync.mutex_unlock(&s.mutex)
	return task
}

// Release never waits for IO. The worker discards a cancelled in-flight result.
// Do not use the task pointer after release.
release :: proc(s: ^Service, task: ^Task) {
	if task == nil { return }
	sync.mutex_lock(&s.mutex)
	task.cancelled = true
	sync.cond_signal(&s.wake)
	sync.mutex_unlock(&s.mutex)
}

status :: proc(s: ^Service, task: ^Task) -> State {
	if task == nil { return .None }
	sync.mutex_lock(&s.mutex)
	state := task.state
	sync.mutex_unlock(&s.mutex)
	return state
}

revision :: proc(s: ^Service, task: ^Task) -> u64 {
	if task == nil { return 0 }
	sync.mutex_lock(&s.mutex)
	value := task.revision
	sync.mutex_unlock(&s.mutex)
	return value
}

// Moves ownership to the caller. Results never borrow storage from the worker.
take :: proc(s: ^Service, task: ^Task) -> (Result, bool) {
	if task == nil { return {}, false }
	sync.mutex_lock(&s.mutex)
	defer sync.mutex_unlock(&s.mutex)
	if !task.ready { return {}, false }
	result := task.result
	task.result, task.ready = {}, false
	return result, true
}

// Retire a large directory/pixel snapshot off-thread rather than freeing every
// filename in the UI update. Caller must stop using its contents immediately.
retire :: proc(s: ^Service, result: Result) {
	context.allocator = runtime.heap_allocator()
	sync.mutex_lock(&s.mutex)
	append(&s.garbage, result)
	sync.cond_signal(&s.wake)
	sync.mutex_unlock(&s.mutex)
}

destroy_result :: proc(result: Result) {
	context.allocator = runtime.heap_allocator()
	for entry in result.entries {
		os.file_info_delete(entry.info, context.allocator)
		delete(entry.sort_name)
	}
	delete(result.entries)
	delete(result.pixels)
	delete(result.path)
	delete(result.error)
}

destroy :: proc(s: ^Service) {
	if s == nil { return }
	context.allocator = runtime.heap_allocator()
	sync.mutex_lock(&s.mutex)
	s.stopping = true
	sync.cond_signal(&s.wake)
	sync.mutex_unlock(&s.mutex)
	thread.join(s.worker)
	thread.destroy(s.worker)
	for task in s.tasks { destroy_task(task) }
	for result in s.garbage { destroy_result(result) }
	delete(s.tasks); delete(s.garbage)
	free(s)
}

@(private) destroy_task :: proc(task: ^Task) {
	destroy_result(task.result)
	delete(task.path)
	free(task)
}

@(private) worker_main :: proc(data: rawptr) {
	context.allocator = runtime.heap_allocator()
	s := cast(^Service)data
	for {
		free_all(context.temp_allocator)
		sync.mutex_lock(&s.mutex)
		if s.stopping { sync.mutex_unlock(&s.mutex); return }
		if len(s.garbage) > 0 {
			result := pop(&s.garbage)
			sync.mutex_unlock(&s.mutex)
			destroy_result(result)
			continue
		}
		task: ^Task
		for _ in 0..<len(s.tasks) {
			s.cursor %= len(s.tasks)
			candidate := s.tasks[s.cursor]
			s.cursor += 1
			if candidate.cancelled || candidate.pending || (candidate.watch && time.tick_since(candidate.checked) >= POLL_INTERVAL) {
				task = candidate
				break
			}
		}
		if task == nil {
			sync.cond_wait_with_timeout(&s.wake, &s.mutex, POLL_INTERVAL)
			sync.mutex_unlock(&s.mutex)
			continue
		}
		if task.cancelled {
			index := s.cursor - 1
			s.tasks[index] = s.tasks[len(s.tasks) - 1]
			pop(&s.tasks)
			sync.mutex_unlock(&s.mutex)
			destroy_task(task)
			continue
		}
		force := task.pending
		task.pending = false
		sync.mutex_unlock(&s.mutex)
		stamp := file_stamp(task.path)
		if force || stamp != task.stamp {
			sync.mutex_lock(&s.mutex)
			task.state = .Reading
			sync.mutex_unlock(&s.mutex)
			result := read_resource(task.path, task.kind, task.extent)
			sync.mutex_lock(&s.mutex)
			old := task.result
			task.result = {}
			if !task.cancelled {
				task.revision += 1
				result.revision = task.revision
				task.result, task.ready, task.state = result, true, .Done
			} else { append(&s.garbage, result) }
			sync.mutex_unlock(&s.mutex)
			destroy_result(old)
		}
		task.stamp, task.checked = stamp, time.tick_now()
	}
}

@(private) file_stamp :: proc(path: string) -> Stamp {
	info, err := os.stat(path, context.allocator)
	if err != nil { return {} }
	defer os.file_info_delete(info, context.allocator)
	return {true, info.size, info.modification_time, info.inode, info.device, info.mode}
}

@(private) read_resource :: proc(path: string, kind: Kind, extent: int) -> Result {
	result: Result
	if filepath.is_abs(path) {
		result.path, _ = filepath.clean(path)
	} else {
		working, err := os.getwd(context.allocator)
		if err != nil { result.error = fmt.aprintf("%v", err); return result }
		result.path, _ = filepath.join({working, path})
		delete(working)
	}
	if kind == .Image {
		decoded, err := images.load_file(result.path)
		if err != nil { result.error = fmt.aprintf("%v", err); return result }
		defer images.destroy(decoded)
		result.size = {decoded.width, decoded.height}
		if extent > 0 && max(decoded.width, decoded.height) > extent {
			factor := f64(extent) / f64(max(decoded.width, decoded.height))
			result.size = {max(1, int(f64(decoded.width) * factor)), max(1, int(f64(decoded.height) * factor))}
		}
		result.pixels = make([]u8, result.size.x * result.size.y * 4)
		if result.size == ([2]int{decoded.width, decoded.height}) {
			copy(result.pixels, decoded.pixels.buf[:])
			return result
		}
		// Box averaging when reducing: thumbnails remain premultiplied RGBA.
		for y in 0..<result.size.y {
			for x in 0..<result.size.x {
				x0, x1 := x * decoded.width / result.size.x, (x + 1) * decoded.width / result.size.x
				y0, y1 := y * decoded.height / result.size.y, (y + 1) * decoded.height / result.size.y
				sum: [4]u64
				for sy in y0..<y1 { for sx in x0..<x1 {
					for c in 0..<4 { sum[c] += u64(decoded.pixels.buf[(sy * decoded.width + sx) * 4 + c]) }
				} }
				for c in 0..<4 { result.pixels[(y * result.size.x + x) * 4 + c] = u8(sum[c] / u64((x1 - x0) * (y1 - y0))) }
			}
		}
		return result
	}
	infos, err := os.read_all_directory_by_path(result.path, context.allocator)
	if err != nil { result.error = fmt.aprintf("%v", err); return result }
	for info in infos {
		directory := info.type == .Directory
		if info.type == .Symlink {
			target, stat_err := os.stat(info.fullpath, context.allocator)
			if stat_err == nil { directory = target.type == .Directory; os.file_info_delete(target, context.allocator) }
		}
		if directory { result.folders += 1 }
		append(&result.entries, Entry{info, directory, strings.to_lower(info.name)})
	}
	delete(infos)
	slice.sort_by(result.entries[:], proc(a, b: Entry) -> bool {
		if a.directory != b.directory { return a.directory }
		if a.sort_name != b.sort_name { return a.sort_name < b.sort_name }
		return a.info.name < b.info.name
	})
	return result
}
