package widgets
import ui "../core"

Check_State :: enum {Off, On, Mixed}
checkbox_state :: proc(value: string, checked: ^Check_State, enabled: bool = true, loc := #caller_location) -> bool {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	a := interact(enabled)
	if a.clicked { checked^ = .Off if checked^ == .On else .On }
	r := ui.current_rect(); box := ui.Rect{r.position + [2]f32{2, (r.size.y-16)/2}, {16, 16}}
	fill(box, colors.control_disabled if !enabled else colors.checked if checked^ != .Off else colors.control, 3)
	fill(box, colors.checked if checked^ != .Off && enabled else colors.control_border, 3, 1)
	if checked^ == .On { icon_at(.Check, box, colors.on_checked if enabled else colors.text_disabled) }
	if checked^ == .Mixed { icon_at(.Minus, inset(box, 3), colors.on_checked if enabled else colors.text_disabled) }
	text_at(value, {r.position + [2]f32{26, 0}, {max(0, r.size.x-26), r.size.y}}, colors.text if enabled else colors.text_disabled)
	focus_ring(r, enabled)
	return a.clicked
}
checkbox :: proc(value: string, checked: ^bool, enabled: bool = true, loc := #caller_location) -> bool {
	s := Check_State.On if checked^ else Check_State.Off
	changed := checkbox_state(value, &s, enabled, loc)
	checked^ = s == .On
	return changed
}
radio :: proc(value: string, selected: bool, enabled: bool = true, tab_stop: bool = true, take_focus: bool = false, loc := #caller_location) -> bool {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	a := interact(enabled); r := ui.current_rect()
	ui.focusable(enabled && (tab_stop || a.clicked))
	if enabled && (take_focus || a.clicked) { ui.request_focus() }
	box := ui.Rect{r.position + [2]f32{2, (r.size.y-16)/2}, {16, 16}}
	fill(box, colors.checked if selected && enabled else colors.control_border, 8, 1.5)
	if selected { fill(inset(box, 4), colors.checked if enabled else colors.text_disabled, 4) }
	text_at(value, {r.position + [2]f32{26, 0}, {max(0, r.size.x-26), r.size.y}}, colors.text if enabled else colors.text_disabled)
	focus_ring(r, enabled)
	return a.clicked
}
toggle :: proc(value: string, checked: ^bool, enabled: bool = true, loc := #caller_location) -> bool {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	a := interact(enabled); if a.clicked { checked^ = !checked^ }
	r := ui.current_rect(); box := ui.Rect{r.position + [2]f32{0, (r.size.y-18)/2}, {32, 18}}
	amount := ui.animate_f32(1 if checked^ else 0)
	fill(box, colors.track + ((colors.checked if enabled else colors.control_disabled) - colors.track)*amount, 9)
	thumb := ui.Rect{box.position + [2]f32{2+14*amount, 2}, {14, 14}}
	fill(thumb, colors.thumb if enabled else colors.thumb_disabled, 7)
	fill(thumb, colors.thumb_border, 7, 0.5)
	text_at(value, {r.position + [2]f32{40, 0}, {max(0, r.size.x-40), r.size.y}}, colors.text if enabled else colors.text_disabled)
	focus_ring(r, enabled); return a.clicked
}

// Static vertical radio group: one Tab stop, arrows select and move focus.
radio_group :: proc(items: []string, selected: ^int, enabled: bool = true, loc := #caller_location) -> bool {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	if len(items) == 0 { return false }
	before := selected^
	selected^ = clamp(selected^, 0, len(items)-1)
	move := false
	if enabled && ui.focused() {
		input := ui.current_frame().input
		if .Left in input.keys_pressed || .Up in input.keys_pressed { selected^ = (selected^+len(items)-1)%len(items); move = true }
		if .Right in input.keys_pressed || .Down in input.keys_pressed { selected^ = (selected^+1)%len(items); move = true }
	}
	for item, index in items {
		ui.open_rect(.Top, theme.height, key = index)
		if radio(item, selected^ == index, enabled, tab_stop = selected^ == index, take_focus = move && selected^ == index) { selected^ = index }
		ui.close_rect()
	}
	return before != selected^
}
