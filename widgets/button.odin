package widgets

import ui "../core"

Button_Kind :: enum {Secondary, Primary, Destructive, Quiet}
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

button :: proc(value: string, kind: Button_Kind = .Secondary, enabled: bool = true, loc := #caller_location) -> bool {
	ui.open_rect_at(ui.current_rect(), loc = loc)
	defer ui.close_rect()
	r := ui.current_rect()
	a := interact(enabled)
	base := theme.surface
	if kind == .Primary { base = theme.selection }
	if kind == .Destructive { base = theme.danger }
	if kind == .Quiet { base = theme.background }
	target := theme.pressed if a.down else theme.hover
	amount := ui.animate_f32(1 if a.hover || a.down else 0)
	fill(r, base + (target - base)*amount, theme.radius)
	if kind != .Quiet { fill(r, theme.border if kind == .Secondary else theme.accent if kind == .Primary else theme.danger, theme.radius, 1) }
	focus_ring(r, enabled)
	text_at(value, inset(r, 3), theme.text if enabled else theme.muted, .Center)
	return a.clicked
}

Icon :: enum {Close, Up, Down, Left, Right, Plus, Minus, More, Check, Search}
// Geometry-based icons have no font dependency or missing-glyph surprises.
@(private)
icon_at :: proc(icon: Icon, r: ui.Rect, color: ui.Color) {
	p := r.position + (r.size - [2]f32{12, 12})/2
	if icon == .Search {
		fill({p, {9, 9}}, color, 4.5, 1.5)
		for n in 0..<4 { fill({p + [2]f32{7+f32(n), 7+f32(n)}, {2, 2}}, color, 1) }
	}
	if icon == .Plus || icon == .Minus { fill({p + [2]f32{0, 5}, {12, 2}}, color) }
	if icon == .Plus { fill({p + [2]f32{5, 0}, {2, 12}}, color) }
	if icon == .More { for x in 0..<3 { fill({p + [2]f32{f32(x*5), 5}, {2, 2}}, color, 1) } }
	for n in 0..<6 {
		x := f32(n)
		#partial switch icon {
		case .Close:
			fill({p + [2]f32{x*2, x*2}, {2, 2}}, color)
			fill({p + [2]f32{10-x*2, x*2}, {2, 2}}, color)
		case .Up: fill({p + [2]f32{5-x, x+2}, {2, 2}}, color); fill({p + [2]f32{5+x, x+2}, {2, 2}}, color)
		case .Down: fill({p + [2]f32{x, x+2}, {2, 2}}, color); fill({p + [2]f32{10-x, x+2}, {2, 2}}, color)
		case .Left: fill({p + [2]f32{x+2, 5-x}, {2, 2}}, color); fill({p + [2]f32{x+2, 5+x}, {2, 2}}, color)
		case .Right: fill({p + [2]f32{7-x, 5-x}, {2, 2}}, color); fill({p + [2]f32{7-x, 5+x}, {2, 2}}, color)
		case .Check:
			fill({p + [2]f32{5+x, 8-x}, {2, 2}}, color)
			if n < 3 { fill({p + [2]f32{2+x, 5+x}, {2, 2}}, color) }
		}
	}
}
icon_button :: proc(icon: Icon, enabled: bool = true, loc := #caller_location) -> bool {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	r := ui.current_rect(); a := interact(enabled)
	fill(r, theme.pressed if a.down else theme.hover if a.hover else theme.surface, theme.radius)
	focus_ring(r, enabled)
	icon_at(icon, r, theme.text if enabled else theme.muted)
	return a.clicked
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
