package widgets
import ui "../core"

// Caller owns the editor and its text/selection. Initialize/destroy using the
// core editor API, or keep it under ui.state with destroy_text_edit as cleanup.
text_field :: proc(editor: ^ui.Text_Edit, placeholder: string = "", enabled: bool = true, invalid: bool = false, loc := #caller_location) -> ui.Text_Edit_Result {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	r := ui.current_rect()
	ui.focusable(enabled)
	fill(r, theme.background, theme.radius)
	fill(r, theme.danger if invalid else theme.border, theme.radius, 1)
	focus_ring(r, enabled)
	return field_editor(editor, placeholder, enabled)
}

@(private)
field_editor :: proc(editor: ^ui.Text_Edit, placeholder: string, enabled: bool, align: ui.Text_Align = .Start) -> ui.Text_Edit_Result {
	ui.focusable(enabled)
	ui.pad2(0, theme.padding)
	if !enabled { label(placeholder if ui.text_edit_value(editor) == "" else ui.text_edit_value(editor), muted = true, align = align); return {} }
	result := ui.edit_text(editor, current_font, theme.font_size, theme.text, theme.selection, align = align)
	if ui.text_edit_value(editor) == "" { label(placeholder, muted = true) }
	return result
}

search_field :: proc(editor: ^ui.Text_Edit, placeholder: string = "Find", enabled: bool = true, loc := #caller_location) -> ui.Text_Edit_Result {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	bounds := ui.current_rect()
	fill(bounds, theme.background, theme.radius)
	ui.open_rect(.Right, theme.height)
	clear := field_button(.Close, enabled && ui.text_edit_value(editor) != "")
	ui.close_rect()
	ui.open_rect(.Left, theme.height)
	ui.set_hit_test(false)
	icon_at(.Search, ui.current_rect(), theme.muted)
	ui.close_rect()
	if clear { ui.destroy_text_edit(editor); ui.init_text_edit(editor); ui.request_focus() }
	r := field_editor(editor, placeholder, enabled)
	fill(bounds, theme.accent if enabled && ui.focused() else theme.border, theme.radius, 1)
	r.changed = r.changed || clear
	return r
}
