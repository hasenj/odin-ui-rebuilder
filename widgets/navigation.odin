package widgets
import ui "../core"

// Return activation independently of selection, so the caller owns semantics.
list_item :: proc(value: string, selected: bool = false, enabled: bool = true, loc := #caller_location) -> bool {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	a := interact(enabled); r := ui.current_rect()
	if selected || a.hover || a.down { fill(r, colors.control_pressed if a.down else colors.selection if selected else colors.control_hover, theme.radius) }
	focus_ring(inset(r, 2), enabled)
	text_at(value, inset(r, 5), colors.text_disabled if !enabled else colors.on_selection if selected && !a.down else colors.text)
	return a.clicked
}

// Index-based convenience for static lists. For reorderable/dynamic items use
// ui.open_identity(key = your_distinct_integer) and list_item with caller state.
tabs :: proc(items: []string, selected: ^int, segmented: bool = false, loc := #caller_location) -> bool {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	if len(items) == 0 { return false }
	before := selected^; selected^ = clamp(selected^, 0, len(items)-1)
	s := ui.state(Tab_State, cleanup = destroy_tabs)
	input := ui.current_frame().input
	move := false
	for id, index in s.ids {
		if id != ui.direct_focus() { continue }
		if .Left in input.keys_pressed { selected^ = (index+len(items)-1)%len(items); move = true }
		if .Right in input.keys_pressed { selected^ = (index+1)%len(items); move = true }
		if .Home in input.keys_pressed { selected^ = 0; move = true }
		if .End in input.keys_pressed { selected^ = len(items)-1; move = true }
	}
	clear(&s.ids)
	r := ui.current_rect(); width := r.size.x/f32(len(items))
	for item, index in items {
		ui.open_rect_at({r.position + [2]f32{f32(index)*width, 0}, {width, r.size.y}}, key = index)
		append(&s.ids, ui.current_identity())
		a := interact(true)
		if a.clicked { selected^ = index; ui.request_focus() }
		ui.focusable(index == selected^)
		if move && index == selected^ { ui.request_focus() }
		box := ui.current_rect()
		if segmented {
			fill(box, colors.selection if selected^ == index else colors.control_hover if a.hover else colors.control, theme.radius)
			focus_ring(inset(box, 2))
		} else {
			// Extend the rounded surface below a clip to keep only its top
			// corners rounded. The straight bottom edge joins the underline.
			ui.open_clip(box)
			radius := min(theme.radius, min(box.size.x, box.size.y)*0.5)
			top := box; top.size.y += radius + 1
			if a.hover { fill(top, colors.selection if selected^ == index else colors.control_hover, radius) }
			focused := ui.direct_focus() == ui.current_identity()
			if focused { fill(top, colors.focus, radius, 1) }
			if selected^ == index || focused {
				line := min(box.size.y, f32(2) if selected^ == index else f32(1))
				fill({box.position + [2]f32{0, box.size.y-line}, {box.size.x, line}}, colors.tab_indicator if selected^ == index else colors.focus)
			}
			ui.close_clip()
		}
		text_at(item, inset(box, 3), (colors.on_selection if segmented || a.hover else colors.text) if selected^ == index else colors.text_muted, .Center)
		ui.close_rect()
	}
	return selected^ != before
}

// On true, a content scope stays open. The caller supplies the remaining
// content height and closes with disclosure_close. No hidden measuring pass.
disclosure_open :: proc(value: string, expanded: ^bool, loc := #caller_location) -> bool {
	ui.open_rect_at(ui.current_rect(), loc = loc)
	ui.open_rect(.Top, theme.height)
	a := interact(true)
	if a.clicked { expanded^ = !expanded^ }
	input := ui.current_frame().input
	if ui.direct_focus() == ui.current_identity() {
		if .Right in input.keys_pressed { expanded^ = true }
		if .Left in input.keys_pressed { expanded^ = false }
	}
	r := ui.current_rect(); fill(r, colors.control_hover if a.hover else colors.control, theme.radius); focus_ring(inset(r, 2))
	icon_at(.Down if expanded^ else .Right, {r.position, {24, r.size.y}}, colors.text_muted)
	text_at(value, {r.position + [2]f32{28, 0}, {max(0, r.size.x-28), r.size.y}}, colors.text)
	ui.close_rect()
	if !expanded^ { ui.close_rect(); return false }
	ui.pad4(4, 4, 0, 16)
	return true
}
disclosure_close :: proc() { ui.close_rect() }
// Tree branches and accordions share disclosure behavior; nested scopes retain
// independent keys. Leaves are ordinary list_item calls.
tree_open :: disclosure_open
tree_close :: disclosure_close
accordion_open :: disclosure_open
accordion_close :: disclosure_close

@(private) Tab_State :: struct {ids: [dynamic]ui.Identity}
@(private) destroy_tabs :: proc(s: ^Tab_State) { delete(s.ids) }
