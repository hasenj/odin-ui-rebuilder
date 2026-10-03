package file_manager

import ui "../../core"
import "core:strings"
import "core:path/filepath"
import "core:fmt"

columns :: proc(kind, size: string, heading: bool) {
	width := ui.current_rect().size.x
	if width >= 300 {
		ui.open_rect(.Right, 84)
		label(size, 11 if heading else 13, muted, align = .End)
		ui.close_rect()
	}
	if width >= 500 {
		ui.open_rect(.Right, 112)
		label(kind, 11 if heading else 13, muted)
		ui.close_rect()
	}
}

file_kind :: proc(entry: Entry) -> string {
	if entry.directory { return "Folder" }
	ext := filepath.ext(entry.sort_name)
	switch ext {
	case ".png": return "PNG image"
	case ".jpg", ".jpeg": return "JPEG image"
	case ".txt", ".md": return "Text file"
	case ".zip", ".gz", ".tar": return "Archive"
	case ".pdf": return "PDF document"
	case: return "File"
	}
}
file_size :: proc(size: i64, buffer: []u8) -> string {
	if size >= 1000000000 { return fmt.bprintf(buffer, "%.1f GB", f64(size) / 1000000000) }
	if size >= 1000000 { return fmt.bprintf(buffer, "%.1f MB", f64(size) / 1000000) }
	if size >= 1000 { return fmt.bprintf(buffer, "%.0f KB", f64(size) / 1000) }
	return fmt.bprintf(buffer, "%d B", size)
}
file_icon :: proc(entry: Entry) {
	r := ui.current_rect()
	box := ui.Rect{r.position + [2]f32{0, (r.size.y - 36) / 2}, {36, 36}}
	ui.open_rect_at(box)
	ui.paint(color = {0.93, 0.96, 0.96, 1}, corners = 6)
	if entry.directory {
		ui.open_rect_at({box.position + [2]f32{5, 8}, {12, 6}})
		ui.paint(color = blue, corners = 2)
		ui.close_rect()
		ui.open_rect_at({box.position + [2]f32{5, 12}, {26, 18}})
		ui.paint(color = {0.30, 0.63, 0.64, 1}, corners = 3)
		ui.close_rect()
	} else {
		ext := filepath.ext(entry.sort_name)
		if strings.equal_fold(ext, ".png") || strings.equal_fold(ext, ".jpg") || strings.equal_fold(ext, ".jpeg") {
			result := ui.image_file(entry.info.fullpath, max_extent = 128)
			if result.image != (ui.Image{}) {
				size, ok := ui.image_size(result.image)
				if ok {
					factor := min(36 / f32(size.x), 36 / f32(size.y))
					drawn := [2]f32{f32(size.x), f32(size.y)} * factor
					ui.open_rect_at({box.position + (box.size - drawn) / 2, drawn})
					ui.paint(img = result.image, corners = 4)
					ui.close_rect()
				}
			} else { label("!" if result.error != "" else "...", 14, muted, align = .Center) }
		} else {
			ui.open_rect_at({box.position + [2]f32{9, 5}, {18, 26}})
			ui.paint(color = {0.77, 0.82, 0.86, 1}, corners = 2)
			ui.pad(4)
			for _ in 0..<3 {
				ui.open_rect(.Top, 2); ui.paint(color = {1, 1, 1, 1}); ui.close_rect()
				ui.pad4(3, 0, 0, 0)
			}
			ui.close_rect()
		}
	}
	ui.close_rect()
}
