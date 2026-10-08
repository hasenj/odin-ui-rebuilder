package widgets
import ui "../core"

// Caller owns only the model value; identity-retained core state handles editing.
text_field :: proc(value: ui.Text_Value, placeholder: string = "", enabled: bool = true, invalid: bool = false, loc := #caller_location, allocator := context.allocator) -> ui.Text_Edit_Result {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	r := ui.current_rect()
	ui.focusable(enabled)
	fill(r, colors.field if enabled else colors.field_disabled, theme.radius)
	fill(r, colors.error if invalid else colors.control_border, theme.radius, 1)
	focus_ring(r, enabled)
	return field_editor(value, placeholder, enabled, allocator = allocator)
}

@(private)
field_editor :: proc(value: ui.Text_Value, placeholder: string, enabled: bool, align: ui.Text_Align = .Start, allocator := context.allocator, clear: bool = false) -> ui.Text_Edit_Result {
	ui.pad2(0, theme.padding)
	result := ui.edit_text(value, current_font, theme.font_size, colors.text if enabled else colors.text_disabled,
		colors.text_selection, align = align, allocator = allocator, enabled = enabled, clear = clear)
	if result.empty && !result.composing { text_at(placeholder, ui.current_rect(), colors.placeholder if enabled else colors.text_disabled) }
	return result
}

// Internal numeric editor: the numeric widget already owns and synchronizes
// its formatted working text. It shares the same core editing implementation.
@(private)
field_editor_state :: proc(editor: ^ui.Text_Edit, placeholder: string, enabled: bool, align: ui.Text_Align = .Start) -> ui.Text_Edit_Result {
	ui.pad2(0, theme.padding)
	result := ui.edit_text_state(editor, current_font, theme.font_size, colors.text if enabled else colors.text_disabled, colors.text_selection, align, enabled = enabled)
	if ui.text_edit_value(editor) == "" { text_at(placeholder, ui.current_rect(), colors.placeholder) }
	return result
}

search_field :: proc(value: ui.Text_Value, placeholder: string = "Find", enabled: bool = true, loc := #caller_location, allocator := context.allocator) -> ui.Text_Edit_Result {
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	bounds := ui.current_rect()
	fill(bounds, colors.field if enabled else colors.field_disabled, theme.radius)
	ui.open_rect(.Right, theme.height)
	clear := field_button(.Close, enabled)
	ui.close_rect()
	ui.open_rect(.Left, theme.height)
	ui.set_hit_test(false)
	icon_at(.Search, ui.current_rect(), colors.text_muted if enabled else colors.text_disabled)
	ui.close_rect()
	if clear { ui.request_focus() }
	r := field_editor(value, placeholder, enabled, allocator = allocator, clear = clear)
	fill(bounds, colors.focus if enabled && ui.focused() else colors.control_border, theme.radius, 1)
	return r
}
