package widgets
import ui "../core"
import "base:runtime"

@(private) Widget_Frame :: struct {top, previous_top: ui.Identity, icons: Icon_Set}
@(private) frame_state: ^Widget_Frame
@(private) Popup_State :: struct {seen: bool, items: [dynamic]ui.Identity}
@(private) Overlay :: struct {
	visible: ^bool,
	state: ^Popup_State,
	menu, fresh: bool,
	bounds: ui.Rect,
	actions: ui.Rect,
	body_open, actions_reserved, actions_open, actions_built: bool,
}
@(private) overlays: [32]Overlay
@(private) overlay_depth: int

// Clamp to this window. Anchored popups flip above/left when needed before
// clamping. Native OS panels remain a separate application/window decision.
popup_bounds :: proc(anchor: ui.Rect, size: [2]f32, side: bool = false) -> ui.Rect {
	window := ui.current_frame().size
	r := ui.Rect{anchor.position + [2]f32{anchor.size.x+4, 0} if side else anchor.position + [2]f32{0, anchor.size.y+4}, size}
	if side && r.position.x+r.size.x > window.x { r.position.x = anchor.position.x-r.size.x-4 }
	if !side && r.position.y+r.size.y > window.y { r.position.y = anchor.position.y-r.size.y-4 }
	r.size = {min(max(0, size.x), max(0, window.x-8)), min(max(0, size.y), max(0, window.y-8))}
	r.position = {clamp(r.position.x, 4, max(4, window.x-r.size.x-4)), clamp(r.position.y, 4, max(4, window.y-r.size.y-4))}
	return r
}
@(private)
contains :: proc(r: ui.Rect, p: [2]f32) -> bool { return p.x >= r.position.x && p.y >= r.position.y && p.x < r.position.x+r.size.x && p.y < r.position.y+r.size.y }

@(private)
open_overlay :: proc(visible: ^bool, bounds: ui.Rect, modal, menu: bool, loc: runtime.Source_Code_Location) -> bool {
	if !visible^ { return false }
	assert(frame_state != nil, "Call widgets.begin once per window update")
	assert(overlay_depth < len(overlays))
	ui.open_layer(100 + i32(overlay_depth)*10, escape_clip = true)
	ui.open_rect_at({size = ui.current_frame().size}, loc = loc)
	root := ui.current_identity()
	ui.focus_fence()
	s := ui.state(Popup_State, cleanup = destroy_popup)
	input := ui.current_frame().input
	fresh := !s.seen
	if s.seen && frame_state.previous_top == root {
		if .Escape in input.keys_pressed && .Escape not_in input.text.handled_keys { visible^ = false }
		if !modal && .Left in input.mouse_pressed && !contains(bounds, input.mouse_position) {
			visible^ = false
			inside_parent := false
			for i in 0..<overlay_depth { if contains(overlays[i].bounds, input.mouse_position) { inside_parent = true } }
			if !inside_parent { for i in 0..<overlay_depth { if overlays[i].menu { overlays[i].visible^ = false } } }
		}
	}
	s.seen = true; clear(&s.items)
	// Keep the full-window hit barrier for the closing frame; dismissal clicks
	// never activate the controls underneath the popup.
	if !visible^ { ui.close_rect(); ui.close_layer(); return false }
	frame_state.top = root
	if modal { ui.paint(color = colors.modal_scrim) }
	ui.open_rect_at(bounds)
	// Broad ambient shadow plus a tighter contact edge: visible against dark
	// panels too. Emit before the content clip so the shadow can extend outside.
	ui.shadow(color = colors.shadow_ambient, blur = 12, offset = {0, 6}, corners = theme.radius)
	ui.shadow(color = colors.shadow_contact, blur = 2, offset = {0, 2}, corners = theme.radius)
	ui.paint(color = colors.overlay, corners = theme.radius)
	ui.stroke(colors.overlay_border, corners = theme.radius)
	ui.open_clip()
	ui.pad(theme.padding)
	overlays[overlay_depth] = {visible = visible, state = s, menu = menu, fresh = fresh, bounds = bounds}; overlay_depth += 1
	return true
}

popover_open :: proc(visible: ^bool, anchor: ui.Rect, size: [2]f32, loc := #caller_location) -> bool {
	return open_overlay(visible, popup_bounds(anchor, size), false, false, loc)
}
popover_close :: proc() { close_overlay() }

// Reserve an optional bottom action area before exposing the clipped body.
// Build its buttons later using dialog_actions_open/close, after body content.
dialog_open :: proc(title: string, visible: ^bool, size: [2]f32 = {400, 238}, actions_height: f32 = 0, loc := #caller_location) -> bool {
	window := ui.current_frame().size
	actual := [2]f32{min(size.x, max(0, window.x-16)), min(size.y, max(0, window.y-16))}
	if !open_overlay(visible, {(window-actual)/2, actual}, true, false, loc) { return false }
	ui.pad(max(0, theme.dialog_padding-theme.padding))
	o := &overlays[overlay_depth-1]
	if actions_height > 0 {
		o.actions_reserved = true
		ui.open_rect(.Bottom, actions_height+theme.padding*2+1)
		o.actions = ui.current_rect()
		ui.close_rect()
	}
	ui.open_rect(.Top, theme.height)
	ui.open_rect(.Right, theme.height)
	if icon_button(.Close) { visible^ = false }
	ui.close_rect(); text_at(title, ui.current_rect(), colors.text, size = theme.font_size+3); ui.close_rect()
	ui.pad4(theme.padding*2, 0, theme.padding*2, 0)
	ui.open_rect_at(ui.current_rect()); ui.open_clip()
	o.body_open = true
	return true
}
dialog_actions_open :: proc() {
	assert(overlay_depth > 0)
	o := &overlays[overlay_depth-1]
	assert(o.body_open && o.actions_reserved && !o.actions_built, "Reserve actions_height in dialog_open; build actions once after the body")
	ui.close_clip(); ui.close_rect(); o.body_open = false
	ui.open_rect_at(o.actions)
	separator()
	ui.pad4(theme.padding*2+1, 0, 0, 0)
	o.actions_open = true; o.actions_built = true
}
dialog_actions_close :: proc() {
	assert(overlay_depth > 0 && overlays[overlay_depth-1].actions_open)
	ui.close_rect(); overlays[overlay_depth-1].actions_open = false
}
dialog_close :: proc() {
	assert(overlay_depth > 0)
	o := &overlays[overlay_depth-1]
	assert(!o.actions_open, "Close the dialog action scope first")
	if o.body_open { ui.close_clip(); ui.close_rect() }
	close_overlay()
}

@(private)
close_overlay :: proc() {
	assert(overlay_depth > 0)
	overlay_depth -= 1
	o := overlays[overlay_depth]
	if o.menu && len(o.state.items) > 0 {
		input := ui.current_frame().input
		index := -1
		for id, i in o.state.items { if id == ui.direct_focus() { index = i } }
		if index >= 0 {
			next := index
			if .Down in input.keys_pressed { next = (index+1)%len(o.state.items) }
			if .Up in input.keys_pressed { next = (index+len(o.state.items)-1)%len(o.state.items) }
			if .Home in input.keys_pressed { next = 0 }
			if .End in input.keys_pressed { next = len(o.state.items)-1 }
			if next != index { ui.request_focus(o.state.items[next]) }
		}
	}
	ui.close_clip(); ui.close_rect(); ui.close_rect(); ui.close_layer()
}

// Tooltip has no interactive children and never participates in hit testing or
// focus. Anchor hover is taken from the current identity before opening it.
tooltip :: proc(value: string, delay: f64 = 0.5, loc := #caller_location) {
	hover := ui.hovered()
	anchor := ui.current_bounds()
	ui.open_identity(loc = loc)
	s := ui.state(Tooltip_State)
	if !hover { s.since = ui.current_frame().time; s.active = false; ui.close_identity(); return }
	if !s.active { s.active = true; s.since = ui.current_frame().time }
	if ui.current_frame().time-s.since >= delay {
		metrics, _ := ui.measure_text(value, current_font, theme.font_size)
		r := popup_bounds(anchor, {metrics.width+16, theme.height})
		ui.open_layer(500, escape_clip = true); ui.open_rect_at(r); ui.set_hit_test(false)
		ui.shadow(color = colors.shadow_ambient, blur = 5); ui.paint(color = colors.overlay, corners = theme.radius); ui.stroke(colors.overlay_border, corners = theme.radius)
		text_at(value, inset(r, 5), colors.text)
		ui.close_rect(); ui.close_layer()
	}
	ui.close_identity()
}
@(private) Tooltip_State :: struct {active: bool, since: f64}

Toast :: struct {visible: bool, expires: f64}
show_toast :: proc(toast: ^Toast, duration: f64 = 4) { toast^ = {true, ui.current_frame().time + duration} }
// App owns timeout/lifetime. Returns true for the optional action (e.g. Undo).
toast :: proc(value: string, state: ^Toast, action: string = "", loc := #caller_location) -> bool {
	if !state.visible { return false }
	if ui.current_frame().time >= state.expires { state.visible = false; return false }
	window := ui.current_frame().size
	size := [2]f32{min(360, max(0, window.x-16)), 44}
	ui.open_layer(450, escape_clip = true)
	ui.open_rect_at({{(window.x-size.x)/2, max(0, window.y-size.y-12)}, size}, loc = loc)
	defer { ui.close_rect(); ui.close_layer() }
	ui.shadow(color = colors.shadow_ambient); ui.paint(color = colors.overlay, corners = theme.radius); ui.stroke(colors.overlay_border, corners = theme.radius); ui.pad(6)
	ui.open_rect(.Right, 28); if icon_button(.Close) { state.visible = false }; ui.close_rect()
	clicked := false
	if action != "" { ui.open_rect(.Right, 60); clicked = button(action, .Quiet); ui.close_rect() }
	label(value)
	if clicked { state.visible = false }
	return clicked
}

// In-window, modeless content panel. Returns Close activation; the scope always
// opens and must be paired with panel_close. Native windows are not created.
panel_open :: proc(title: string, closable: bool = true, loc := #caller_location) -> bool {
	ui.open_rect_at(ui.current_rect(), loc = loc)
	ui.paint(color = colors.surface, corners = theme.radius)
	ui.stroke(colors.border, corners = theme.radius)
	ui.open_clip(); ui.pad(theme.padding)
	ui.open_rect(.Top, theme.height)
	close := false
	if closable { ui.open_rect(.Right, theme.height); close = icon_button(.Close); ui.close_rect() }
	label(title); ui.close_rect()
	ui.pad4(theme.gap, 0, 0, 0)
	return close
}
panel_close :: proc() { ui.close_clip(); ui.close_rect() }

@(private) destroy_popup :: proc(s: ^Popup_State) { delete(s.items) }
