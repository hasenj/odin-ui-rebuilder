package widgets
import ui "../core"

@(private) Scrollbar_State :: struct {dragging: bool, grab: f32, previous: ui.Mouse_Buttons}
// Call inside an open_scroll scope BEFORE its children. This paints an overlay
// track at the viewport's right edge, and may adjust the current canvas offset.
scrollbar :: proc(loc := #caller_location) {
	scroll := ui.current_scroll()
	if scroll.max_offset.y <= 0 || scroll.viewport.size.y <= 0 { return }
	track := ui.Rect{scroll.viewport.position + [2]f32{max(0, scroll.viewport.size.x-10), 0}, {10, scroll.viewport.size.y}}
	height := min(track.size.y, max(20, track.size.y*track.size.y/scroll.content_size.y))
	travel := track.size.y-height
	y := travel*scroll.offset.y/scroll.max_offset.y
	ui.open_rect_at(track, loc = loc)
	s := ui.state(Scrollbar_State)
	input := ui.current_frame().input
	pressed := input.mouse_pressed | (input.mouse_buttons & ~s.previous)
	released := input.mouse_released | (s.previous & ~input.mouse_buttons)
	s.previous = input.mouse_buttons
	if input.mouse_cancelled { s.dragging = false }
	if ui.hovered() && .Left in pressed && !input.mouse_cancelled {
		s.dragging = true
		local := input.mouse_position.y-track.position.y
		s.grab = local-y if local >= y && local < y+height else height/2
	}
	changed := s.dragging
	if s.dragging {
		y = clamp(input.mouse_position.y-track.position.y-s.grab, 0, travel)
		if .Left in released || .Left not_in input.mouse_buttons { s.dragging = false }
	}
	fill({track.position + [2]f32{3, y}, {4, height}}, colors.scrollbar_hover if s.dragging || ui.hovered() else colors.scrollbar, 2)
	ui.close_rect()
	if changed && travel > 0 { ui.scroll_to({scroll.offset.x, y/travel*scroll.max_offset.y}) }
}
