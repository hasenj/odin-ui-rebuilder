package ui

import "base:intrinsics"
import "core:math"
import "core:slice"

// Caller-owned, per-window view state. Durable selection/edit data belongs in
// the application model, keyed by item key: ordinary offscreen UI state expires.
// The focused row (including a focused descendant), its neighbors and endpoints
// remain declared so Tab can traverse the whole list without O(N) UI work.
Virtual_List :: struct {
	first, end: int, // Visible half-open interval.
	indices: [dynamic]int, // Visible rows + at most five keyboard targets, sorted.
	rows: [dynamic]Virtual_Row,
	keys: [dynamic]Identity_Key,
	by_key: map[Identity_Key]int,
	canvas: Rect,
	row_height: f32,
	owner: Identity,
	focus_index: int,
}
Virtual_Row :: struct {index: int, id: Identity, key: Identity_Key}

// O(N) only when items change, not every frame. Keys must be unique in this
// list; their integer type is part of the identity. Insertion/reorder keeps the
// focused key and retained declared-row state. Removing it clears its focus.
virtual_list_set_items :: proc(list: ^Virtual_List, keys: []$T) where intrinsics.type_is_integer(T) {
	clear(&list.by_key)
	resize(&list.keys, len(keys))
	for key, i in keys {
		normalized := integer_identity_key(key)
		_, exists := list.by_key[normalized]
		assert(!exists, "Virtual list item keys must be unique")
		list.keys[i] = normalized
		list.by_key[normalized] = i
	}
}

virtual_list_count :: proc(list: ^Virtual_List) -> int { return len(list.keys) }

// Uses the most recent declared rows but resolves their keys in the current
// item model. Works after insertion/reordering and before rebuilding the rows.
virtual_list_focused_index :: proc(list: ^Virtual_List) -> int {
	for row in list.rows {
		if focused(row.id) {
			if index, found := list.by_key[row.key]; found { return index }
			return -1
		}
	}
	return -1
}

open_virtual_list :: proc{open_virtual_list_implicit, open_virtual_list_keyed}
@(private)
open_virtual_list_implicit :: proc(list: ^Virtual_List, row_height: f32, reveal: int = -1, loc := #caller_location) {
	open_virtual_list_key(list, row_height, reveal, Identity_Key{location = loc})
}
@(private)
open_virtual_list_keyed :: proc(list: ^Virtual_List, row_height: f32, key: $T, reveal: int = -1) where intrinsics.type_is_integer(T) {
	open_virtual_list_key(list, row_height, reveal, integer_identity_key(key))
}
@(private)
open_virtual_list_key :: proc(list: ^Virtual_List, row_height: f32, reveal: int, key: Identity_Key) {
	assert(row_height > 0 && valid_length(row_height * f32(len(list.keys))), "Invalid virtual list row height/extent")
	assert(list.owner == (Identity{}), "Virtual list already open")
	open_scroll_key({current_rect().size.x, row_height * f32(len(list.keys))}, key)
	list.owner = current_identity()
	list.row_height = row_height
	focused_index := virtual_list_focused_index(list)
	if focused_index < 0 {
		for row in list.rows { if focused(row.id) { clear_focus(); break } }
	}
	if reveal >= 0 && reveal < len(list.keys) {
		state := current_scroll()
		top := row_height * f32(reveal)
		offset := state.offset.y
		if top < offset || row_height > state.viewport.size.y { offset = top } else if top + row_height > offset + state.viewport.size.y {
			offset = top + row_height - state.viewport.size.y
		}
		scroll_to({state.offset.x, offset})
		focused_index = reveal // Include its Tab neighbors on the first reveal frame.
	}
	list.focus_index = focused_index
}

// Call once after any scroll_to()/scrollbar adjustment, then build every returned
// row. Deferring range preparation makes scrollbars effective in the same frame.
virtual_list_rows :: proc(list: ^Virtual_List) -> []int {
	assert(current_identity() == list.owner, "Not in this virtual list scope")
	focused_index, row_height := list.focus_index, list.row_height
	state := current_scroll()
	list.canvas = current_rect()
	clear(&list.rows)
	clear(&list.indices)
	count := len(list.keys)
	list.first = clamp(int(math.floor(state.offset.y / row_height)), 0, count)
	list.end = clamp(int(math.ceil((state.offset.y + state.viewport.size.y) / row_height)), list.first, count)
	if state.viewport.size.y <= 0 || state.viewport.size.x <= 0 { list.end = list.first }
	for i in list.first..<list.end { append(&list.indices, i) }
	if count > 0 {
		append(&list.indices, 0, count - 1)
		if focused_index >= 0 {
			for i in max(0, focused_index - 1)..<min(count, focused_index + 2) { append(&list.indices, i) }
		}
	}
	slice.sort(list.indices[:])
	unique := 0
	for index in list.indices {
		if unique == 0 || list.indices[unique - 1] != index { list.indices[unique] = index; unique += 1 }
	}
	resize(&list.indices, unique)
	return list.indices[:]
}

// Call once for each returned index, in order. Close with close_rect(). Painting
// is optional for offscreen targets; declaring their interaction is required.
open_virtual_row :: proc(list: ^Virtual_List, index: int, focusable: bool = true) -> (visible: bool) {
	assert(current_identity() == list.owner && index >= 0 && index < len(list.keys), "Invalid virtual row scope/index")
	open_rect_at_key({list.canvas.position + [2]f32{0, f32(index) * list.row_height}, {list.canvas.size.x, list.row_height}}, list.keys[index])
	current_hit_entry().focusable = focusable
	append(&list.rows, Virtual_Row{index, current_identity(), list.keys[index]})
	return index >= list.first && index < list.end
}

close_virtual_list :: proc(list: ^Virtual_List) {
	assert(current_identity() == list.owner, "Unclosed virtual row")
	list.owner = {}
	close_scroll()
}

destroy_virtual_list :: proc(list: ^Virtual_List) {
	delete(list.keys); delete(list.by_key); delete(list.rows); delete(list.indices)
	list^ = {}
}
