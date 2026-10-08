package demo17

import ui "../../core"
import w "../../widgets"
import "core:os"
import "core:fmt"
import "core:slice"

Face_Key :: distinct u32
list: ui.Virtual_List
keys: [dynamic]Face_Key
font, preview: ui.Font
selected: Face_Key
sample: [dynamic]u8
initialized, capture: bool
step: int

main :: proc() {
	append(&sample, "Hello 日本語 مرحبا — café")
	defer delete(sample)
	defer ui.destroy_virtual_list(&list)
	defer delete(keys)
	if len(os.args) > 1 && os.args[1] == "--capture" {
		capture = true
		frames := [?]ui.Capture_Frame{
			{size = {820, 700}, scale = 1},
			{size = {820, 700}, scale = 2, path = "bin/demo17-fonts.png"},
			{size = {820, 700}, scale = 1, input = {mouse_inside = true, mouse_position = {200, 440}, scroll_delta = {0, 1400}}},
			{size = {820, 700}, scale = 1, path = "bin/demo17-scrolled.png"},
			{size = {420, 500}, scale = 2, path = "bin/demo17-compact.png"},
		}
		result := ui.capture_frames(update, frames[:]); assert(result.error == .None)
		fmt.printf("Verified system font browser: %d faces, lazy named lookup, mixed-script editing and bounded virtual rows\n", len(keys))
		return
	}
	ui.open_window("System fonts", 820, 700, update, transparent = false, frame_timing = .Summary)
}

update :: proc() {
	if !initialized {
		initialized = true
		err: ui.Text_Error
		font, err = ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf", "Interface"); assert(err == .None)
		count, error := ui.discover_fonts(); assert(error == .None)
		for i in 0..<count { append(&keys, Face_Key(i + 1)) }
		slice.sort_by(keys[:], proc(a, b: Face_Key) -> bool {
			x, y := ui.font_catalog_info(int(a)-1), ui.font_catalog_info(int(b)-1)
			return x.family < y.family if x.family != y.family else x.style < y.style
		})
		ui.virtual_list_set_items(&list, keys[:])
		preview = font
		for key in keys {
			info := ui.font_catalog_info(int(key)-1)
			if (info.family == "Helvetica" || info.family == "DejaVu Sans") && info.style == "Regular" {
				selected = key
				preview, _ = ui.find_font(info.family) // Exercise lazy name resolution.
				break
			}
		}
		if selected == 0 && count > 0 { select_face(keys[0]) }
	}
	w.begin(font)
	ui.paint(color = w.colors.background)
	ui.pad(18)
	ui.open_rect(.Top, 36)
	ui.open_rect(.Right, 120)
	if w.button("Reverse list") { slice.reverse(keys[:]); ui.virtual_list_set_items(&list, keys[:]) }
	ui.close_rect()
	w.label("System fonts"); ui.close_rect()
	ui.open_rect(.Top, 32)
	w.label(fmt.tprintf("%d installed faces · select a row to preview · Tab to navigate", len(keys)), muted = true)
	ui.close_rect()
	ui.open_rect(.Top, 160)
	ui.paint(color = w.colors.control, corners = 8)
	ui.pad(12)
	ui.open_rect(.Top, 28)
	if selected != 0 {
		info := ui.font_catalog_info(int(selected)-1)
		w.label(fmt.tprintf("%s · %s", info.family, info.style))
	} else { w.label("No outline fonts discovered") }
	ui.close_rect()
	ui.open_rect(.Top, 48)
	layout, err := ui.layout_text_fit("A little type goes a long way.", preview, ui.current_rect().size.x, size = 30, max_height = ui.current_rect().size.y)
	assert(err == .None)
	err = ui.draw_text_layout(layout, color = w.colors.text, valign = .Center); assert(err == .None)
	ui.close_rect()
	ui.open_rect(.Top, 44)
	w.begin(preview)
	result := w.text_field(&sample)
	assert(result.error == .None)
	w.begin(font)
	ui.close_rect()
	ui.close_rect()
	ui.pad4(12, 0, 0, 0)
	ui.open_rect(.Bottom, 26)
	w.label("Fallback follows the selected face. Color emoji comes later.", muted = true)
	ui.close_rect()
	ui.open_virtual_list(&list, 36)
	w.scrollbar()
	for index in ui.virtual_list_rows(&list) {
		visible := ui.open_virtual_row(&list, index)
		key := keys[index]
		input := ui.current_frame().input
		if ui.focused() || (ui.hovered() && .Left in input.mouse_pressed) { if selected != key { select_face(key) } }
		if visible {
			if selected == key || ui.hovered() { ui.paint(color = w.colors.control_hover, corners = 4) }
			ui.pad2(0, 10)
			info := ui.font_catalog_info(int(key)-1)
			w.label(fmt.tprintf("%s  /  %s", info.family, info.style))
		}
		ui.close_rect()
	}
	assert(len(list.rows) <= list.end - list.first + 5)
	ui.close_virtual_list(&list)
	if capture && step == 3 { assert(list.first > 10) }
	step += 1
}

select_face :: proc(key: Face_Key) {
	loaded, err := ui.load_catalog_font(int(key)-1)
	if err == .None { selected, preview = key, loaded }
}
