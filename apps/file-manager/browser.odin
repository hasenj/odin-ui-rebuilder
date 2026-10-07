package file_manager

import "../../core/files"
import "core:strings"
import "core:fmt"

Entry :: files.Entry
Browser :: struct {
	path, pending, error: string,
	entries: [dynamic]Entry,
	generation, directory_generation, next_key: u64,
	entry_keys: [dynamic]u64,
	folders, reads: int,
	initialized: bool,
	state: files.State,
	service: ^files.Service,
	active, opening: ^files.Task,
	refresh: bool,
}

// Only enqueue here. Normalizing paths, reading, sorting and watching all run
// on the shared file-loader implementation, never on the UI thread.
browse :: proc(browser: ^Browser, path: string) {
	if browser.service == nil { browser.service = files.create() }
	files.release(browser.service, browser.opening)
	browser.opening = files.request(browser.service, path, .Directory)
	browser.state = .Reading
}

// Returns true when a snapshot replaces the displayed listing. A failed
// navigation keeps the old directory and its watcher alive. Worker disposal
// avoids an O(N) filename-free loop in the update as well.
poll_browser :: proc(browser: ^Browser) -> bool {
	changed := false
	if browser.opening != nil {
		if result, ready := files.take(browser.service, browser.opening); ready {
			browser.reads += 1
			if result.error == "" {
				files.release(browser.service, browser.active)
				browser.active, browser.opening = browser.opening, nil
				apply_snapshot(browser, result)
				changed = true
			} else {
				delete(browser.error)
				browser.error = fmt.aprintf("Could not open folder: %s", result.error)
				files.retire(browser.service, result)
				// With no displayed directory, keep watching so a missing starting
				// folder can recover automatically when it is created.
				if browser.active != nil { files.release(browser.service, browser.opening); browser.opening = nil }
			}
		}
	}
	if browser.active != nil {
		if result, ready := files.take(browser.service, browser.active); ready {
			browser.reads += 1
			if result.error == "" { apply_snapshot(browser, result); changed = true } else {
				delete(browser.error)
				browser.error = fmt.aprintf("Folder unavailable: %s", result.error)
				files.retire(browser.service, result)
			}
		}
	}
	if browser.opening != nil { browser.state = files.status(browser.service, browser.opening) } else if browser.active != nil {
		browser.state = files.status(browser.service, browser.active)
	}
	return changed
}

apply_snapshot :: proc(browser: ^Browser, result: files.Result) {
	browser.refresh = browser.path == result.path
	// Match unchanged names before retiring the old worker-owned snapshot.
	previous: map[string]u64
	if browser.refresh {
		for entry, i in browser.entries { previous[entry.info.name] = browser.entry_keys[i] }
	} else { browser.directory_generation += 1 }
	keys := make([dynamic]u64, len(result.entries))
	for entry, i in result.entries {
		key, found := previous[entry.info.name]
		if !found { browser.next_key += 1; key = browser.next_key }
		keys[i] = key
	}
	delete(previous)
	delete(browser.entry_keys)
	browser.entry_keys = keys
	files.retire(browser.service, files.Result{path = browser.path, entries = browser.entries})
	delete(browser.error)
	browser.path, browser.entries, browser.folders, browser.error = result.path, result.entries, result.folders, ""
	browser.generation += 1 // Rebuild the virtual key index and reset typeahead.
}

queue_directory :: proc(browser: ^Browser, path: string) {
	delete(browser.pending)
	browser.pending = strings.clone(path)
}

destroy_browser :: proc(browser: ^Browser) {
	delete(browser.entry_keys)
	files.destroy(browser.service)
	files.destroy_result(files.Result{path = browser.path, entries = browser.entries})
	delete(browser.pending)
	delete(browser.error)
	browser^ = {}
}
