package widgets

import ui "../core"

Button_Kind :: enum {Secondary, Primary, Destructive, Quiet}
Button_Sizing :: enum {Fixed, Content}
@(private) Action :: struct {armed, space: bool, previous: ui.Mouse_Buttons}
@(private) Response :: struct {clicked, down, hover: bool}

// Enter is press-activated; Space is release-activated. Mouse activation needs
// a press inside followed by release inside. Cancelling/focus loss discards it.
@(private)
interact :: proc(enabled: bool) -> Response {
	ui.focusable(enabled)
	s := ui.state(Action)
	i := ui.current_frame().input
	pressed := i.mouse_pressed | (i.mouse_buttons & ~s.previous)
	released := i.mouse_released | (s.previous & ~i.mouse_buttons)
	s.previous = i.mouse_buttons
	r := Response{hover = enabled && ui.hovered()}
	if !enabled || i.mouse_cancelled { s.armed, s.space = false, false; return r }
	if .Left in pressed { s.armed = r.hover }
	if .Left in released { r.clicked = s.armed && r.hover; s.armed = false }
	if .Left not_in i.mouse_buttons && .Left not_in pressed { s.armed = false }
	focused := ui.direct_focus() == ui.current_identity()
	if !focused || i.modifiers & {.Control, .Alt, .Super} != {} { s.space = false }
	if focused && i.modifiers & {.Control, .Alt, .Super} == {} {
		if (.Enter in i.keys_pressed && .Enter not_in i.text.handled_keys) || (.KeypadEnter in i.keys_pressed && .KeypadEnter not_in i.text.handled_keys) { r.clicked = true }
		if .Space in i.keys_pressed && .Space not_in i.text.handled_keys { s.space = true }
		if .Space in i.keys_released && s.space { r.clicked = true; s.space = false }
	}
	r.down = (s.armed && r.hover) || s.space
	return r
}

button :: proc(value: string, kind: Button_Kind = .Secondary, enabled: bool = true, loc := #caller_location,
	sizing: Button_Sizing = .Fixed, size: [2]f32 = {}, icon: ui.Icon_Glyph = {}) -> bool {
	local := ui.layout_active()
	assert(sizing != .Content || local, "Content-sized buttons require ui.open_layout")
	assert(sizing != .Content || size == ([2]f32{}), "Content-sized buttons do not take a fixed size")
	if sizing == .Fixed && (local || size != ([2]f32{})) {
		assert(size.x > 0 && size.y > 0, "Fixed buttons inside local layout require a positive size")
	}
	if local {
		style := ui.Layout_Style{padding = {theme.padding, theme.padding*1.5}, align = .Center}
		if sizing == .Fixed { style.width = ui.layout_fixed(size.x); style.height = ui.layout_fixed(size.y); style.padding = {3, 3} }
		ui.open_box(style, loc = loc)
	} else {
		r := ui.current_rect()
		if size != ([2]f32{}) { r.size = {min(r.size.x, size.x), min(r.size.y, size.y)} }
		ui.open_rect_at(r, loc = loc)
	}
	defer { if local { ui.close_box() } else { ui.close_rect() } }
	a := interact(enabled)
	base := theme.surface
	if kind == .Primary { base = theme.selection }
	if kind == .Destructive { base = theme.danger }
	target := theme.pressed if a.down else theme.hover
	amount := ui.animate_f32(1 if a.hover || a.down else 0)
	fill_color := base + (target - base)*amount
	if kind == .Quiet { fill_color = target; fill_color.a *= amount }
	if fill_color.a > 0 { ui.paint(color = fill_color, corners = theme.radius) }
	if kind != .Quiet { ui.stroke(theme.border if kind == .Secondary else theme.accent if kind == .Primary else theme.danger, corners = theme.radius) }
	if enabled && ui.direct_focus() == ui.current_identity() {
		// A local layout can touch its enclosing clip or adjacent siblings.
		ui.stroke(theme.accent, corners = theme.radius if local else theme.radius+2, inset = 1 if local else -2)
	}
	color := theme.text if enabled else theme.muted
	if local {
		style: ui.Layout_Style
		if sizing == .Fixed { style.width = ui.layout_fixed(size.x); style.height = ui.layout_fixed(size.y) }
		ui.text_item(value, current_font, theme.font_size, color, style = style, fit = true, align = .Center, valign = .Center,
			icon = icon, icon_size = theme.icon_size, icon_gap = theme.gap)
	} else {
		_ = ui.draw_label(value, current_font, inset(ui.current_rect(), 3), theme.font_size, color, icon, theme.icon_size, theme.gap)
	}
	return a.clicked
}

// Built-in names are mapped to the same glyph primitive applications can supply.
@(private)
icon_at :: proc(name: Icon, r: ui.Rect, color: ui.Color) {
	size := min(theme.icon_size, min(r.size.x, r.size.y))
	_ = ui.draw_icon(icon(name), {r.position+(r.size-[2]f32{size, size})/2, {size, size}}, color)
}
icon_button :: proc(icon: Icon, enabled: bool = true, loc := #caller_location) -> bool {
	return button("", .Quiet, enabled, loc, icon = current_icons[icon])
}

// A button within a shared field border. Keep both hover and keyboard focus
// inside its segment so adjacent editors cannot cover the outline.
@(private)
field_button :: proc(icon: Icon, enabled: bool = true, loc := #caller_location) -> bool {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	r := ui.current_rect(); a := interact(enabled)
	if a.hover || a.down { fill(inset(r, 2), theme.pressed if a.down else theme.hover, max(0, theme.radius-1)) }
	focus_ring(inset(r, 4), enabled)
	icon_at(icon, r, theme.text if enabled else theme.muted)
	return a.clicked
}
