package ui

import fonts "text"

Icon_Glyph :: fonts.Icon_Glyph

resolve_icon :: proc(font: Font, codepoint: rune) -> (Icon_Glyph, Text_Error) {
	_ = current_frame()
	return fonts.resolve_icon(&active_state.text, font, codepoint)
}

// Paint within a resolved destination, without adding layout/identity nodes.
// The caller chooses size/color; the icon stores only its physical font/glyph.
draw_icon :: proc(icon: Icon_Glyph, rect: Rect, color: Color = {1, 1, 1, 1}) -> Text_Error {
	assert(!layout_active(), "Use icon_item inside a local layout")
	frame := current_frame()
	return fonts.draw_icon(&active_state.text, frame.renderer, icon, rect.position, rect.size, frame.scale, color, &frame.surfaces)
}

// A square icon leaf for content layout, drawn after its bounds are resolved.
icon_item :: proc(icon: Icon_Glyph, size: f32 = 16, color: Color = {1, 1, 1, 1}, loc := #caller_location) {
	open_box({width = layout_fixed(size), height = layout_fixed(size)}, loc = loc)
	store := &active_state.layout
	append(&store.commands, Layout_Command{kind = .Icon, node = store.stack[len(store.stack)-1], icon = icon, color = color})
	close_box()
}

// One fitted label, optionally with a leading icon. The icon keeps its requested
// size while text fits the remaining width. Both are clipped to the destination.
draw_label :: proc(value: string, font: Font_Ref, rect: Rect, size: f32 = 16, color: Color = {1, 1, 1, 1}, icon: Icon_Glyph = {}, icon_size: f32 = 16, gap: f32 = 6, min_scale: f32 = 0.5) -> Text_Error {
	assert(!layout_active() && valid_length(icon_size) && valid_length(gap))
	label: Text_Layout
	if value != "" {
		extra := icon_size+gap if icon.font != 0 else 0
		err: Text_Error
		label, err = layout_text_fit(value, font, max(0, rect.size.x-extra), size, min_scale, max_height = rect.size.y)
		if err != .None { return err }
	}
	open_clip(rect); defer close_clip()
	return draw_label_layout(label, value != "", rect, color, icon, icon_size, gap, .Center, .Center)
}

@(private)
draw_label_layout :: proc(label: Text_Layout, has_text: bool, rect: Rect, color: Color, icon: Icon_Glyph, icon_size, gap: f32, align, valign: Text_Align) -> Text_Error {
	frame := current_frame()
	if icon.font == 0 {
		if !has_text { return .None }
		return fonts.draw_layout(&active_state.text, frame.renderer, label, rect.position, rect.size, color, &frame.surfaces, align, valign)
	}
	space := icon_size+gap if has_text else icon_size
	width := space+label.width
	offset := max(0, rect.size.x-width)
	x := rect.position.x + (offset/2 if align == .Center else offset if align == .End else 0)
	height := max(icon_size, label.height)
	offset_y := max(0, rect.size.y-height)
	y := rect.position.y + (offset_y/2 if valign == .Center else offset_y if valign == .End else 0)
	err := draw_icon(icon, {{x, y+max(0, (height-icon_size)/2)}, {min(icon_size, rect.size.x), min(icon_size, rect.size.y)}}, color)
	if has_text && rect.size.x > space && rect.size.y > 0 {
		text_err := fonts.draw_layout(&active_state.text, frame.renderer, label, {x+space, y},
			{max(0, rect.position.x+rect.size.x-x-space), min(height, rect.size.y)}, color, &frame.surfaces, .Start, .Center)
		if err == .None { err = text_err }
	}
	return err
}
