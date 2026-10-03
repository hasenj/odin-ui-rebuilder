package file_manager

import ui "../../core"
import "core:math"
import "core:slice"

Row_Identity :: struct {index: int, id: ui.Identity}
List_View :: struct {
	generation: u64,
	first, end: int,
	indices: [dynamic]int,
	rows: [dynamic]Row_Identity,
}
list: List_View

// Construct only the visible range, plus at most five focus targets. Folders
// are sorted first, so keyboard neighbors and traversal endpoints are O(1).
// Declaring those targets in index order preserves Tab/Shift-Tab across the
// viewport boundary; core can reveal them before the next frame is built.
prepare_list :: proc(count, folders: int, generation: u64, offset, height: f32) {
	focused := -1
	if list.generation == generation {
		for row in list.rows {
			if row.id == ui.direct_focus() { focused = row.index; break }
		}
	}
	list.generation = generation
	clear(&list.rows)
	clear(&list.indices)
	list.first = clamp(int(math.floor(offset / row_height)), 0, count)
	list.end = clamp(int(math.ceil((offset + height) / row_height)), list.first, count)
	if height <= 0 { list.end = list.first }
	for i in list.first..<list.end { append(&list.indices, i) }
	if folders > 0 {
		append(&list.indices, 0, folders - 1)
		if focused >= 0 && focused < folders {
			for i in max(0, focused - 1)..<min(folders, focused + 2) { append(&list.indices, i) }
		}
	}
	slice.sort(list.indices[:])
	// Deduplicate visible rows and focus targets; each identity enters once.
	unique := 0
	for index in list.indices {
		if unique == 0 || list.indices[unique - 1] != index {
			list.indices[unique] = index
			unique += 1
		}
	}
	resize(&list.indices, unique)
}

destroy_list :: proc() {
	delete(list.indices)
	delete(list.rows)
	list = {}
}
