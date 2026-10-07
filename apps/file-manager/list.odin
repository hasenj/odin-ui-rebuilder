package file_manager

import ui "../../core"
import edit "../../core/edit"

List_View :: struct {
	generation: u64,
	search: Typeahead,
	using view: ui.Virtual_List,
}
list: List_View

// Refresh the O(N) key index only when the directory snapshot changes.
prepare_list_items :: proc() {
	if list.generation == browser.generation { return }
	keys := make([]u64, len(browser.entries), context.temp_allocator)
	for _, i in browser.entries {
		keys[i] = browser.entry_keys[i] if len(browser.entry_keys) == len(browser.entries) else u64(i + 1)
	}
	ui.virtual_list_set_items(&list.view, keys)
	list.generation = browser.generation
}

destroy_list :: proc() {
	edit.destroy(&list.search.buffer)
	ui.destroy_virtual_list(&list.view)
	list = {}
}
