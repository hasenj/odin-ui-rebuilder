package app14

import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:fmt"

Entry :: struct {
	info: os.File_Info,
	directory: bool,
	sort_name: string,
}

Browser :: struct {
	path, pending, error: string,
	entries: [dynamic]Entry,
	generation: u64,
	folders: int,
	reads: int,
	initialized: bool,
}

// A snapshot owned by the application. Filesystem work happens only on entry,
// never while drawing an unchanged directory. Failed navigation preserves it.
browse :: proc(browser: ^Browser, path: string) -> bool {
	browser.reads += 1
	// filepath.abs resolves symlinks on Unix. Keep a lexical path instead so
	// going Up from a linked folder returns to its visible parent.
	absolute: string
	err: os.Error
	if filepath.is_abs(path) {
		absolute, err = filepath.clean(path)
	} else {
		working, working_err := os.getwd(context.allocator)
		if working_err != nil { set_error(browser, working_err); return false }
		absolute, err = filepath.join({working, path})
		delete(working)
	}
	if err != nil { set_error(browser, err); return false }
	infos, read_err := os.read_all_directory_by_path(absolute, context.allocator)
	if read_err != nil {
		delete(absolute)
		set_error(browser, read_err)
		return false
	}
	clear_entries(browser)
	delete(browser.path)
	delete(browser.error)
	browser.path, browser.error = absolute, ""
	browser.folders = 0
	for info in infos {
		directory := info.type == .Directory
		if info.type == .Symlink {
			target, stat_err := os.stat(info.fullpath, context.allocator)
			if stat_err == nil {
				directory = target.type == .Directory
				os.file_info_delete(target, context.allocator)
			}
		}
		if directory { browser.folders += 1 }
		append(&browser.entries, Entry{info, directory, strings.to_lower(info.name)})
	}
	delete(infos) // Entry owns each File_Info's path (and borrowed basename).
	slice.sort_by(browser.entries[:], proc(a, b: Entry) -> bool {
		if a.directory != b.directory { return a.directory }
		if a.sort_name != b.sort_name { return a.sort_name < b.sort_name }
		return a.info.name < b.info.name
	})
	browser.generation += 1
	return true
}

queue_directory :: proc(browser: ^Browser, path: string) {
	delete(browser.pending)
	browser.pending = strings.clone(path)
}

set_error :: proc(browser: ^Browser, err: os.Error) {
	delete(browser.error)
	browser.error = fmt.aprintf("Could not open folder: %v", err)
}

clear_entries :: proc(browser: ^Browser) {
	for entry in browser.entries {
		os.file_info_delete(entry.info, context.allocator)
		delete(entry.sort_name)
	}
	clear(&browser.entries)
}

destroy_browser :: proc(browser: ^Browser) {
	clear_entries(browser)
	delete(browser.entries)
	delete(browser.path)
	delete(browser.pending)
	delete(browser.error)
	browser^ = {}
}
