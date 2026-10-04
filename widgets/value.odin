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
	fill(track, theme.border, 2)
	fill({track.position, {track.size.x*fraction, 4}}, theme.accent if enabled else theme.muted, 2)
	fill({track.position + [2]f32{track.size.x*fraction-7, -5}, {14, 14}}, theme.text if enabled else theme.muted, 7)
	focus_ring(r, enabled)
	return value^ != before
}
progress :: proc(value: f32) {
	r := ui.current_rect(); r.position.y += max(0, (r.size.y-6)/2); r.size.y = min(r.size.y, 6)
	fill(r, theme.border, 3); r.size.x *= clamp(value, 0, 1); fill(r, theme.accent, 3)
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
	ui.open_rect(.Left, theme.height); if icon_button(.Minus, enabled && value^ > low) { value^ = max(low, value^-step) }; ui.close_rect()
	ui.open_rect(.Right, theme.height); if icon_button(.Plus, enabled && value^ < high) { value^ = min(high, value^+step) }; ui.close_rect()
	parsed, valid := strconv.parse_f64(ui.text_edit_value(&s.editor))
	valid = valid && parsed >= low && parsed <= high
	result := text_field(&s.editor, enabled = enabled, invalid = !valid)
	if result.changed { parsed, valid = strconv.parse_f64(ui.text_edit_value(&s.editor)); if valid && parsed >= low && parsed <= high { value^ = parsed } }
	if result.submitted || value^ != before || !ui.focused() {
		if !valid || value^ != parsed { ui.destroy_text_edit(&s.editor); ui.init_text_edit(&s.editor, fmt.tprintf("%g", value^)) }
	}
	s.last = value^
	return before != value^
}
Badge_Kind :: enum {Neutral, Success, Warning, Error}
badge :: proc(value: string, kind: Badge_Kind = .Neutral) {
	color := theme.muted
	switch kind {
	case .Success: color = theme.accent
	case .Warning: color = {0.90, 0.68, 0.25, 1}
	case .Error: color = theme.danger
	case .Neutral:
	}
	fill(ui.current_rect(), theme.surface, theme.radius)
	fill(ui.current_rect(), color, theme.radius, 1)
	text_at(value, inset(ui.current_rect(), 3), color, .Center)
}
