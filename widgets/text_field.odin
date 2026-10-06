package widgets
import ui "../core"

// Caller owns the editor and its text/selection. Initialize/destroy using the
// core editor API, or keep it under ui.state with destroy_text_edit as cleanup.
text_field :: proc(editor: ^ui.Text_Edit, placeholder: string = "", enabled: bool = true, invalid: bool = false, loc := #caller_location) -> ui.Text_Edit_Result {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	r := ui.current_rect()
	ui.focusable(enabled)
	fill(r, colors.field if enabled else colors.field_disabled, theme.radius)
	fill(r, colors.error if invalid else colors.control_border, theme.radius, 1)
	focus_ring(r, enabled)
	return field_editor(editor, placeholder, enabled)
}

@(private)
field_editor :: proc(editor: ^ui.Text_Edit, placeholder: string, enabled: bool, align: ui.Text_Align = .Start) -> ui.Text_Edit_Result {
	ui.focusable(enabled)
	ui.pad2(0, theme.padding)
	if !enabled { text_at(placeholder if ui.text_edit_value(editor) == "" else ui.text_edit_value(editor), ui.current_rect(), colors.text_disabled, align); return {} }
	result := ui.edit_text(editor, current_font, theme.font_size, colors.text, colors.text_selection, align = align)
	if ui.text_edit_value(editor) == "" { text_at(placeholder, ui.current_rect(), colors.placeholder) }
	return result
}

search_field :: proc(editor: ^ui.Text_Edit, placeholder: string = "Find", enabled: bool = true, loc := #caller_location) -> ui.Text_Edit_Result {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	bounds := ui.current_rect()
	fill(bounds, colors.field if enabled else colors.field_disabled, theme.radius)
	ui.open_rect(.Right, theme.height)
	clear := field_button(.Close, enabled && ui.text_edit_value(editor) != "")
	ui.close_rect()
	ui.open_rect(.Left, theme.height)
	ui.set_hit_test(false)
	icon_at(.Search, ui.current_rect(), colors.text_muted if enabled else colors.text_disabled)
	ui.close_rect()
	if clear { ui.destroy_text_edit(editor); ui.init_text_edit(editor); ui.request_focus() }
	r := field_editor(editor, placeholder, enabled)
	fill(bounds, colors.focus if enabled && ui.focused() else colors.control_border, theme.radius, 1)
	r.changed = r.changed || clear
	return r
}
