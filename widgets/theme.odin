// Standard widgets over the public core API. Application data remains owned by
// callers; transient interaction state is retained under each widget identity.
package widgets

import ui "../core"
import builtin "../icons/default"

Theme :: struct {
	background, surface, hover, pressed, text, muted, border, accent, selection, danger: ui.Color,
	height, font_size, radius, padding, gap, dialog_padding: f32,
	icon_size: f32,
}
dark :: Theme{
	background = {0.105, 0.12, 0.135, 1}, surface = {0.145, 0.17, 0.19, 1},
	hover = {0.22, 0.26, 0.29, 1}, pressed = {0.10, 0.27, 0.29, 1},
	text = {0.92, 0.94, 0.95, 1}, muted = {0.58, 0.64, 0.68, 1},
	border = {0.29, 0.34, 0.37, 1}, accent = {0.16, 0.67, 0.64, 1},
	selection = {0.08, 0.29, 0.31, 1}, danger = {0.85, 0.30, 0.30, 1},
	height = 30, font_size = 13, radius = 4, padding = 8, gap = 6, dialog_padding = 24,
	icon_size = 14,
}
// Set once at the beginning of EACH window's update. Font handles are window
// owned. This is transient configuration, never a global store of UI state.
theme: Theme = dark
@(private) current_font: ui.Font_Ref
Icon :: builtin.Name
Icon_Set :: builtin.Set
@(private) current_icons: Icon_Set
// Optional complete replacement for icons used internally by standard widgets.
begin :: proc(font: ui.Font_Ref, style: Theme = dark, icons: Icon_Set = {}) {
	assert(overlay_depth == 0, "Unclosed widget overlay")
	current_font = font; theme = style
	ui.open_identity()
	frame_state = ui.state(Widget_Frame)
	if icons == (Icon_Set{}) {
		if frame_state.icons == (Icon_Set{}) {
			err: ui.Text_Error
			frame_state.icons, err = builtin.load(); assert(err == .None)
		}
		current_icons = frame_state.icons
	} else { current_icons = icons }
	frame_state.previous_top = frame_state.top
	frame_state.top = {}
	ui.close_identity()
}

// Resolve a built-in semantic name using this window's configured icon set.
icon :: proc(name: Icon) -> ui.Icon_Glyph { return current_icons[name] }

@(private)
fill :: proc(r: ui.Rect, color: ui.Color, radius: f32 = 0, border: f32 = 0) {
	if r.size.x <= 0 || r.size.y <= 0 { return }
	append(&ui.current_frame().surfaces, ui.Surface{position = r.position, size = r.size,
		background = color, corner_radius = radius, border_width = border})
}
@(private)
inset :: proc(r: ui.Rect, amount: f32) -> ui.Rect {
	return {r.position + [2]f32{amount, amount}, {max(0, r.size.x - 2*amount), max(0, r.size.y - 2*amount)}}
}
@(private)
text_at :: proc(value: string, r: ui.Rect, color: ui.Color, align: ui.Text_Align = .Start, size: f32 = 0, min_scale: f32 = 1) {
	if r.size.x <= 0 || r.size.y <= 0 || value == "" { return }
	ui.open_rect_at(r)
	ui.set_hit_test(false)
	ui.open_clip()
	layout, err := ui.layout_text_fit(value, current_font, r.size.x, theme.font_size if size == 0 else size, min_scale = min_scale, max_height = r.size.y)
	if err == .None { _ = ui.draw_text_layout(layout, color, align = align, valign = .Center) }
	ui.close_clip()
	ui.close_rect()
}
label :: proc(value: string, muted: bool = false, align: ui.Text_Align = .Start) {
	text_at(value, ui.current_rect(), theme.muted if muted else theme.text, align)
}
separator :: proc() { r := ui.current_rect(); fill({r.position, {r.size.x, 1}}, theme.border) }
@(private)
focus_ring :: proc(r: ui.Rect, enabled: bool = true) {
	if enabled && ui.direct_focus() == ui.current_identity() { fill(inset(r, -2), theme.accent, theme.radius + 2, 1) }
}
