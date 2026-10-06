// Standard widgets over the public core API. Application data remains owned by
// callers; transient interaction state is retained under each widget identity.
package widgets

import ui "../core"
import builtin "../icons/default"

// Geometry and typography metrics stay identical across color schemes.
Theme :: struct {
	height, font_size, radius, padding, gap, dialog_padding, icon_size: f32,
}
default_theme :: Theme{height = 30, font_size = 13, radius = 4, padding = 8, gap = 6, dialog_padding = 24, icon_size = 14}
theme: Theme = default_theme
@(private) current_font: ui.Font_Ref
Icon :: builtin.Name
Icon_Set :: builtin.Set
@(private) current_icons: Icon_Set
// Optional complete replacement for icons used internally by standard widgets.
begin :: proc(font: ui.Font_Ref, scheme: Color_Scheme = dark, style: Theme = default_theme, icons: Icon_Set = {}) {
	assert(overlay_depth == 0, "Unclosed widget overlay")
	current_font = font; theme = style; colors = scheme
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
	text_at(value, ui.current_rect(), colors.text_muted if muted else colors.text, align)
}
separator :: proc() { r := ui.current_rect(); fill({r.position, {r.size.x, 1}}, colors.divider) }
@(private)
focus_ring :: proc(r: ui.Rect, enabled: bool = true) {
	if enabled && ui.direct_focus() == ui.current_identity() { fill(inset(r, -2), colors.focus, theme.radius + 2, 1) }
}
