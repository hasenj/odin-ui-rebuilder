package widgets
import ui "../core"

menu_open :: proc(visible: ^bool, anchor: ui.Rect, size: [2]f32 = {220, 200}, side: bool = false, loc := #caller_location) -> bool {
	if !open_overlay(visible, popup_bounds(anchor, size, side), false, true, loc) { return false }
	ui.open_scroll({ui.current_rect().size.x, max(0, size.y-theme.padding*2)})
	return true
}
menu_close :: proc() { ui.close_scroll(); close_overlay() }
menu_separator :: proc() { ui.open_rect(.Top, theme.gap); ui.pad4(theme.gap/2, 0, 0, 0); separator(); ui.close_rect() }
menu_item :: proc(value: string, shortcut: string = "", checked: bool = false, enabled: bool = true, destructive: bool = false, dismiss: bool = true, loc := #caller_location) -> bool {
	assert(overlay_depth > 0)
	ui.open_rect(.Top, theme.height, loc = loc); defer ui.close_rect()
	a := interact(enabled)
	o := &overlays[overlay_depth-1]
	if enabled && ui.current_rect().size.y > 0 {
		append(&o.state.items, ui.current_identity())
	}
	r := ui.current_rect()
	if a.hover || ui.focused() { fill(r, colors.selection, theme.radius) }
	// The scroll viewport ends at the first/last row. Keep the entire outline
	// inside the row (focus_ring expands its supplied bounds by two pixels).
	focus_ring(inset(r, 3), enabled)
	if checked { icon_at(.Check, {r.position, {22, r.size.y}}, colors.text_disabled if !enabled else colors.on_selection if a.hover || ui.focused() else colors.checked) }
	ui.pad4(0, 6, 0, 24)
	if shortcut != "" { ui.open_rect(.Right, 64); label(shortcut, muted = true, align = .End); ui.close_rect() }
	text_at(value, ui.current_rect(), colors.text_disabled if !enabled else colors.error if destructive else colors.on_selection if a.hover || ui.focused() else colors.text)
	if a.clicked && dismiss { for i in 0..<overlay_depth { overlays[i].visible^ = false } }
	return a.clicked
}
// Explicit submenu state is caller-owned. Opening consumes one parent row;
// when true, add submenu items then call submenu_close(). Right/Enter opens it,
// Escape closes the innermost menu; Left closes it through submenu_close().
submenu_open :: proc(value: string, visible: ^bool, size: [2]f32 = {180, 110}, loc := #caller_location) -> bool {
	if overlays[overlay_depth-1].fresh { visible^ = false }
	ui.open_identity(loc = loc)
	row := ui.current_rect(); row.size.y = min(row.size.y, theme.height)
	if menu_item(value, shortcut = ">", dismiss = false) { visible^ = !visible^ }
	if ui.focused() && .Right in ui.current_frame().input.keys_pressed { visible^ = true }
	if menu_open(visible, row, size, side = true) { return true }
	ui.close_identity(); return false
}
submenu_close :: proc() {
	if .Left in ui.current_frame().input.keys_pressed { overlays[overlay_depth-1].visible^ = false }
	menu_close(); ui.close_identity()
}

@(private) Dropdown_State :: struct {open: bool}
// Label and arrow share one hit target and one keyboard focus stop.
@(private)
dropdown_trigger :: proc(value: string, enabled: bool) -> bool {
	ui.open_rect_at(ui.current_rect()); defer ui.close_rect()
	r := ui.current_rect(); a := interact(enabled)
	amount := ui.animate_f32(1 if a.hover || a.down else 0)
	target := colors.control_pressed if a.down else colors.control_hover
	fill(r, colors.control + (target-colors.control)*amount if enabled else colors.control_disabled, theme.radius)
	fill(r, colors.control_border, theme.radius, 1)
	focus_ring(inset(r, 3), enabled)
	arrow_width := min(28, r.size.x)
	icon_at(.Down, {r.position + [2]f32{r.size.x-arrow_width, 0}, {arrow_width, r.size.y}}, colors.text if enabled else colors.text_disabled)
	text_at(value, inset({r.position, {r.size.x-arrow_width, r.size.y}}, 3), colors.text if enabled else colors.text_disabled, .Center)
	return a.clicked
}

dropdown :: proc(items: []string, selected: ^int, enabled: bool = true, loc := #caller_location) -> bool {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	s := ui.state(Dropdown_State)
	before := selected^
	if len(items) == 0 { s.open = false; _ = dropdown_trigger("—", false); return false }
	selected^ = clamp(selected^, 0, len(items)-1)
	anchor := ui.current_rect()
	if dropdown_trigger(items[selected^], enabled) { s.open = !s.open }
	if !enabled { s.open = false }
	if menu_open(&s.open, anchor, {max(120, anchor.size.x), theme.height*f32(len(items))+theme.padding*2}) {
		for item, index in items {
			ui.open_identity(key = index)
			if menu_item(item, checked = selected^ == index) { selected^ = index }
			ui.close_identity()
		}
		menu_close()
	}
	return selected^ != before
}

@(private) Context_Menu_State :: struct {anchor: ui.Rect}
// Attach to the current rect. The caller still owns open state and menu items.
context_menu_open :: proc(visible: ^bool, size: [2]f32 = {220, 200}, loc := #caller_location) -> bool {
	hover := ui.hovered()
	ui.open_identity(loc = loc)
	s := ui.state(Context_Menu_State)
	input := ui.current_frame().input
	if hover && .Right in input.mouse_pressed {
		visible^ = true; s.anchor = {position = input.mouse_position}
	}
	if menu_open(visible, s.anchor, size) { return true }
	ui.close_identity(); return false
}
context_menu_close :: proc() { menu_close(); ui.close_identity() }
