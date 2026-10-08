package demo16
import ui "../../core"
import w "../../widgets"
import "core:os"
import "core:strings"
import "core:fmt"

font: ui.Font
values: [4]string
checked, switched: bool = true, true
mixed: w.Check_State = .Mixed
radio_value, tab, inspector_tab, segment, selection, sort: int
read_only: bool
amount: f32 = 0.65
number: f64 = 24
expanded, tree: bool = true, true
modal, menu, submenu, popover, inspector_hidden: bool
notice: w.Toast
clicks: int
step: int
capture_mode: bool
light_mode: bool = true
compare_schemes: bool

main :: proc() {
	values = {strings.clone("Project notes"), strings.clone("Untitled/"), strings.clone("notes.txt"), ""}
	defer for value in values { delete(value) }
	if len(os.args) > 1 && (os.args[1] == "--capture" || os.args[1] == "--capture-light") {
		capture_mode = true
		light_mode = os.args[1] == "--capture-light"
		capture_light := light_mode
		frames := [?]ui.Capture_Frame{
			{size = {1040, 820}, scale = 1},
			{size = {1040, 820}, scale = 1, path = "bin/demo16-controls.png", time = 1},
			{size = {1040, 820}, scale = 1, path = "bin/demo16-menu.png", time = 2},
			{size = {1040, 820}, scale = 1, path = "bin/demo16-dialog.png", time = 3},
			{size = {1040, 820}, scale = 1, path = "bin/demo16-popover.png", time = 4},
			{size = {400, 500}, scale = 2, path = "bin/demo16-compact.png", time = 5},
			{size = {1040, 820}, scale = 1, time = 6, input = {mouse_inside = true, mouse_position = {420, 680}}},
			{size = {1040, 820}, scale = 1, time = 7, input = {mouse_inside = true, mouse_position = {420, 680}}},
			{size = {1040, 820}, scale = 1, time = 8, path = "bin/demo16-tooltip.png", input = {mouse_inside = true, mouse_position = {420, 680}}},
			{size = {1040, 820}, scale = 1, time = 9, path = "bin/demo16-toast.png"},
			{size = {400, 500}, scale = 2, time = 10, path = "bin/demo16-dialog-compact.png"},
			{size = {1040, 820}, scale = 2, time = 11},
			{size = {1040, 820}, scale = 2, time = 12, input = {mouse_inside = true, mouse_position = {177, 499}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}},
			{size = {1040, 820}, scale = 2, time = 13, input = {mouse_inside = true, mouse_position = {177, 499}, mouse_released = {.Left}}},
			{size = {1040, 820}, scale = 2, time = 14, path = "bin/demo16-tabs.png", input = {mouse_inside = true, mouse_position = {177, 499}}},
			{size = {1040, 820}, scale = 1, time = 15, path = "bin/demo16-mixed.png"},
			{size = {1040, 820}, scale = 1, time = 16, input = {mouse_inside = true, mouse_position = {950, 29}, mouse_buttons = {.Left}, mouse_pressed = {.Left}}},
			{size = {1040, 820}, scale = 1, time = 17, input = {mouse_inside = true, mouse_position = {950, 29}, mouse_released = {.Left}}},
			{size = {1040, 820}, scale = 1, time = 18, path = "bin/demo16-switched.png"},
		}
		if capture_light {
			for &frame in frames {
				if frame.path != "" { frame.path = fmt.aprintf("bin/demo16-light%s", frame.path[len("bin/demo16"):]) }
			}
		}
		defer if capture_light { for frame in frames { if frame.path != "" { delete(frame.path) } } }
		result := ui.capture_frames(update, frames[:]); assert(result.error == .None)
		fmt.println("Captured widget gallery, menu, dialog, popover and compact layout")
		return
	}
	ui.open_window("Widgets — color schemes", 1040, 820, update, transparent = false, frame_timing = .Summary)
}

row :: proc(height: f32 = 30, loc := #caller_location) { ui.open_rect(.Top, height, loc = loc) }
end_row :: proc() { ui.close_rect(); ui.pad4(6, 0, 0, 0) }

update :: proc() {
	if font == 0 {
		err: ui.Text_Error
		font, err = ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"); assert(err == .None)
	}
	w.begin(font, scheme = w.light if light_mode else w.dark)
	if capture_mode {
		compare_schemes = step == 15
		menu = step == 2; modal = step == 3 || step == 10; popover = step == 4
		if step == 10 { notice.visible = false }
		if step == 9 { w.show_toast(&notice) }
	}
	ui.paint(color = w.colors.background)
	ui.pad(14)
	row(30)
	ui.open_rect(.Right, 140); _ = w.toggle("Light theme", &light_mode); ui.close_rect()
	if ui.current_frame().size.x >= 600 {
		ui.open_rect(.Right, 150); _ = w.checkbox("Mixed preview", &compare_schemes); ui.close_rect()
	}
	w.label("Widget gallery"); end_row()
	row(24); w.label(fmt.tprintf("%d button activations · Tab / Shift-Tab to focus · Arrow keys in menus, tabs and sliders", clicks), muted = true); end_row()
	columns := 3 if ui.current_rect().size.x >= 900 else 2 if ui.current_rect().size.x >= 600 else 1
	width := (max(0, ui.current_rect().size.x-12)-f32(columns-1)*12)/f32(columns)
	height: f32 = 348
	ui.open_scroll({ui.current_rect().size.x, f32((6+columns-1)/columns)*(height+12)})
	w.scrollbar()
	ui.pad4(0, 12, 0, 0)
	canvas := ui.current_rect()
	menu_anchor, pop_anchor: ui.Rect
	for index in 0..<6 {
		ui.open_rect_at({canvas.position + [2]f32{f32(index%columns)*(width+12), f32(index/columns)*(height+12)}, {width, height}}, key = index)
		saved_colors := w.colors
		if compare_schemes && index == 5 { w.colors = w.dark if saved_colors == w.light else w.light }
		titles := [?]string{"Buttons & status", "Text fields", "Selection & values", "Navigation & lists", "Menus & overlays", "Properties"}
		closed := w.panel_open(titles[index], closable = index == 5)
		if closed { inspector_hidden = true }
		switch index {
		case 0:
			row(); if w.button("Save", .Primary, icon = w.icon(.Check)) { clicks += 1 }; end_row()
			row(36)
			ui.open_layout(.Left, {flow = .Row, gap = 8})
			if w.button("Cancel", sizing = .Content, icon = w.icon(.Close)) { clicks += 1 }
			if w.button("Delete selected", .Destructive, sizing = .Content) { clicks += 1 }
			_, content_err := ui.close_layout(); assert(content_err == .None)
			end_row()
			row()
			ui.open_layout(.Left, {flow = .Row, gap = 8})
			if w.button("Fixed size button", sizing = .Fixed, size = {80, 30}, icon = w.icon(.Plus)) { clicks += 1 }
			if w.button("Fixed size button", sizing = .Fixed, size = {140, 30}, icon = w.icon(.Plus)) { clicks += 1 }
			_, fixed_err := ui.close_layout(); assert(fixed_err == .None)
			end_row()
			row(); _ = w.button("Disabled", enabled = false); end_row()
			row(); for icon in ([]w.Icon{.Left, .Up, .Plus, .More}) { ui.open_rect(.Left, 34); if w.icon_button(icon) { clicks += 1 }; ui.close_rect(); ui.pad4(0, 0, 0, 6) }; end_row()
			row(); w.badge("Ready", .Success); end_row()
			row(); w.badge("Warning", .Warning); end_row()
			row(); w.progress(amount); end_row()
		case 1:
			row(); w.label("Name"); end_row()
			row(); w.text_field(&values[0], "Folder name"); end_row()
			row(); w.text_field(&values[1], invalid = true); end_row()
			row(20); w.label("Name cannot contain /", muted = true); end_row()
			row(); w.text_field(&values[2], enabled = false); end_row()
			row(); w.search_field(&values[3], "Find files"); end_row()
			row(); _ = w.number_input(&number, 0, 100); end_row()
		case 2:
			row(); _ = w.checkbox("Show hidden files", &checked); end_row()
			row(); _ = w.checkbox_state("Mixed selection", &mixed); end_row()
			row(); _ = w.toggle("Show extensions", &switched); end_row()
			row(66); _ = w.radio_group({"List", "Grid"}, &radio_value); end_row()
			row(); w.label(fmt.tprintf("Opacity: %.0f%%", amount*100)); end_row()
			row(); _ = w.slider(&amount, 0, 1, 0.01); end_row()
			row(); _ = w.toggle("Unavailable", &switched, enabled = false); end_row()
		case 3:
			row(); _ = w.tabs({"Files", "Activity", "Settings"}, &tab); end_row()
			row(); _ = w.tabs({"List", "Grid", "Details"}, &segment, segmented = true); end_row()
			for item, i in ([]string{"Documents", "Downloads", "Photos"}) { row(); if w.list_item(item, selection == i) { selection = i }; end_row() }
			row(110)
			if w.tree_open("Projects", &tree) { row(); _ = w.list_item("Design"); end_row(); row(); _ = w.list_item("Source", true); end_row(); w.tree_close() }
			end_row()
		case 4:
			row(); _ = w.dropdown({"Name", "Kind", "Size", "Modified"}, &sort); end_row()
			row(); menu_anchor = ui.current_rect(); if w.button("Open context menu") { menu = !menu }; end_row()
			row(); if w.button("Open dialog") { modal = true }; end_row()
			row(); pop_anchor = ui.current_rect(); if w.button("View options") { popover = !popover }; end_row()
			row(); if w.button("Show notification") { w.show_toast(&notice) }; end_row()
			row(); _ = w.button("Hover for tooltip"); w.tooltip("Tooltips respect hover and delay"); end_row()
			row(50); w.label("Menus use Up / Down / Enter.\nEscape dismisses the top overlay.", muted = true); end_row()
		case 5:
			if inspector_hidden { row(); if w.button("Reopen inspector") { inspector_hidden = false }; end_row() } else {
				row(); _ = w.tabs({"General", "Details"}, &inspector_tab); end_row()
				row(); w.text_field(&values[2]); end_row()
				row(); w.label("Location     ~/Documents", muted = true); end_row()
				row(); w.label("Size             12 KB", muted = true); end_row()
				row(); _ = w.checkbox("Read only", &read_only); end_row()
				row(76); if w.accordion_open("Appearance", &expanded) { row(); w.label("Theme: Light" if w.colors == w.light else "Theme: Dark"); end_row(); w.accordion_close() }; end_row()
				row(); if w.button("Apply", .Primary) { w.show_toast(&notice) }; end_row()
			}
		}
		w.panel_close(); ui.close_rect()
		w.colors = saved_colors
	}
	ui.close_scroll()
	if w.menu_open(&menu, menu_anchor, {236, 208}) {
		if w.menu_item("Open", "Enter") { clicks += 1 }
		_ = w.menu_item("Rename", "F2")
		w.menu_separator()
		if w.menu_item("Show hidden files", checked = checked, dismiss = false) { checked = !checked }
		if w.submenu_open("Sort by", &submenu, {160, 106}) { for name in ([]string{"Name", "Kind", "Size"}) { _ = w.menu_item(name) }; w.submenu_close() }
		w.menu_separator(); _ = w.menu_item("Delete", destructive = true)
		w.menu_close()
	}
	if w.dialog_open("Replace file?", &modal, actions_height = 36) {
		row(24); w.label("A file named notes.txt already exists."); end_row()
		row(24); w.label("The existing file will be replaced.", muted = true); end_row()
		w.dialog_actions_open()
		ui.open_rect(.Right, 112); if w.button("Replace", .Destructive) { modal = false; w.show_toast(&notice) }; ui.close_rect()
		ui.pad4(0, 12, 0, 0); ui.open_rect(.Right, 112); if w.button("Cancel") { modal = false }; ui.close_rect()
		w.dialog_actions_close()
		w.dialog_close()
	}
	if w.popover_open(&popover, pop_anchor, {250, 154}) {
		row(); w.label("View options"); end_row()
		row(); _ = w.checkbox("Show hidden files", &checked); end_row()
		row(); _ = w.toggle("Show extensions", &switched); end_row()
		w.popover_close()
	}
	if w.toast("3 files copied", &notice, "Undo") { clicks += 1 }
	step += 1
}
