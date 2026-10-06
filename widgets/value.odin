package widgets
import ui "../core"
import "core:math"
import "core:fmt"
import "core:strconv"

@(private) Slider_State :: struct {dragging: bool, previous: ui.Mouse_Buttons}
slider :: proc(value: ^f32, low: f32 = 0, high: f32 = 1, step: f32 = 0, enabled: bool = true, loc := #caller_location) -> bool {
	assert(high >= low && step >= 0)
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	ui.focusable(enabled)
	s := ui.state(Slider_State); input := ui.current_frame().input; r := ui.current_rect()
	pressed := input.mouse_pressed | (input.mouse_buttons & ~s.previous)
	released := input.mouse_released | (s.previous & ~input.mouse_buttons)
	s.previous = input.mouse_buttons
	before := value^
	if !enabled || input.mouse_cancelled { s.dragging = false }
	if enabled && !input.mouse_cancelled && ui.hovered() && .Left in pressed { s.dragging = true }
	if s.dragging {
		fraction := clamp((input.mouse_position.x-r.position.x-7)/max(1, r.size.x-14), 0, 1)
		value^ = low + (high-low)*fraction
		if step > 0 { value^ = low + math.round((value^-low)/step)*step }
		if .Left in released || .Left not_in input.mouse_buttons { s.dragging = false }
	}
	if enabled && ui.direct_focus() == ui.current_identity() && input.modifiers & {.Control, .Alt, .Super} == {} {
		increment := step if step > 0 else (high-low)/100
		if .Left in input.keys_pressed || .Down in input.keys_pressed { value^ -= increment }
		if .Right in input.keys_pressed || .Up in input.keys_pressed { value^ += increment }
		if .Home in input.keys_pressed { value^ = low }
		if .End in input.keys_pressed { value^ = high }
	}
	value^ = clamp(value^, low, high)
	fraction := (value^-low)/(high-low) if high > low else 0
	track := ui.Rect{r.position + [2]f32{7, r.size.y/2-2}, {max(0, r.size.x-14), 4}}
	fill(track, colors.track, 2)
	fill({track.position, {track.size.x*fraction, 4}}, colors.track_fill if enabled else colors.thumb_disabled, 2)
	thumb := ui.Rect{track.position + [2]f32{track.size.x*fraction-7, -5}, {14, 14}}
	fill(thumb, colors.thumb if enabled else colors.thumb_disabled, 7)
	fill(thumb, colors.thumb_border, 7, 1)
	focus_ring(r, enabled)
	return value^ != before
}
progress :: proc(value: f32) {
	r := ui.current_rect(); r.position.y += max(0, (r.size.y-6)/2); r.size.y = min(r.size.y, 6)
	fill(r, colors.track, 3); r.size.x *= clamp(value, 0, 1); fill(r, colors.track_fill, 3)
}
@(private) Number_State :: struct {editor: ui.Text_Edit, initialized: bool, last: f64}
@(private) destroy_number :: proc(s: ^Number_State) { ui.destroy_text_edit(&s.editor) }
number_input :: proc(value: ^f64, low: f64 = -1e12, high: f64 = 1e12, step: f64 = 1, enabled: bool = true, loc := #caller_location) -> bool {
	assert(high >= low && step > 0)
	ui.open_rect_at(ui.current_rect(), loc = loc); defer ui.close_rect()
	s := ui.state(Number_State, cleanup = destroy_number)
	before := value^
	if enabled && ui.focused() {
		input := ui.current_frame().input
		if .Up in input.keys_pressed { value^ = min(high, value^+step) }
		if .Down in input.keys_pressed { value^ = max(low, value^-step) }
	}
	if !s.initialized || s.last != value^ {
		ui.destroy_text_edit(&s.editor); ui.init_text_edit(&s.editor, fmt.tprintf("%g", value^)); s.initialized = true
	}
	bounds := ui.current_rect()
	fill(bounds, colors.field if enabled else colors.field_disabled, theme.radius)
	ui.open_rect(.Left, theme.height); if field_button(.Minus, enabled && value^ > low) { value^ = max(low, value^-step) }; ui.close_rect()
	ui.open_rect(.Right, theme.height); if field_button(.Plus, enabled && value^ < high) { value^ = min(high, value^+step) }; ui.close_rect()
	center := ui.current_rect()
	fill({center.position, {1, center.size.y}}, colors.control_border)
	fill({center.position + [2]f32{max(0, center.size.x-1), 0}, {min(1, center.size.x), center.size.y}}, colors.control_border)
	parsed, valid := strconv.parse_f64(ui.text_edit_value(&s.editor))
	valid = valid && parsed >= low && parsed <= high
	ui.open_rect_at(center)
	result := field_editor(&s.editor, "", enabled, .Center)
	ui.close_rect()
	fill(bounds, colors.error if !valid else colors.focus if enabled && ui.focused() else colors.control_border, theme.radius, 1)
	if result.changed { parsed, valid = strconv.parse_f64(ui.text_edit_value(&s.editor)); if valid && parsed >= low && parsed <= high { value^ = parsed } }
	if result.submitted || value^ != before || !ui.focused() {
		if !valid || value^ != parsed { ui.destroy_text_edit(&s.editor); ui.init_text_edit(&s.editor, fmt.tprintf("%g", value^)) }
	}
	s.last = value^
	return before != value^
}
Badge_Kind :: enum {Neutral, Success, Warning, Error}
badge :: proc(value: string, kind: Badge_Kind = .Neutral) {
	background, border, text := colors.badge_neutral, colors.badge_neutral_border, colors.badge_neutral_text
	switch kind {
	case .Success: background, border, text = colors.badge_success, colors.badge_success_border, colors.badge_success_text
	case .Warning: background, border, text = colors.badge_warning, colors.badge_warning_border, colors.badge_warning_text
	case .Error: background, border, text = colors.badge_error, colors.badge_error_border, colors.badge_error_text
	case .Neutral:
	}
	fill(ui.current_rect(), background, theme.radius)
	fill(ui.current_rect(), border, theme.radius, 1)
	text_at(value, inset(ui.current_rect(), 3), text, .Center)
}
