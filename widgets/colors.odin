package widgets
import ui "../core"

// Semantic paint roles, independent of geometry. Equal values do not imply
// equal roles: focus, selection, checked controls and progress can vary alone.
Color_Scheme :: struct {
	background, surface, border, divider: ui.Color,
	text, text_muted, text_disabled: ui.Color,
	control, control_hover, control_pressed, control_border, control_disabled: ui.Color,
	primary, primary_hover, primary_pressed, primary_border, on_primary: ui.Color,
	destructive, destructive_hover, destructive_pressed, destructive_border, on_destructive: ui.Color,
	focus, selection, on_selection, tab_indicator: ui.Color,
	field, field_disabled, placeholder, text_selection, error: ui.Color,
	checked, on_checked, track, track_fill, thumb, thumb_border, thumb_disabled: ui.Color,
	scrollbar, scrollbar_hover: ui.Color,
	badge_neutral, badge_neutral_border, badge_neutral_text: ui.Color,
	badge_success, badge_success_border, badge_success_text: ui.Color,
	badge_warning, badge_warning_border, badge_warning_text: ui.Color,
	badge_error, badge_error_border, badge_error_text: ui.Color,
	overlay, overlay_border, modal_scrim, shadow_ambient, shadow_contact: ui.Color,
}

dark :: Color_Scheme{
	background = {0.105, 0.12, 0.135, 1}, surface = {0.145, 0.17, 0.19, 1},
	border = {0.29, 0.34, 0.37, 1}, divider = {0.29, 0.34, 0.37, 1},
	text = {0.92, 0.94, 0.95, 1}, text_muted = {0.58, 0.64, 0.68, 1}, text_disabled = {0.48, 0.54, 0.58, 1},
	control = {0.145, 0.17, 0.19, 1}, control_hover = {0.22, 0.26, 0.29, 1}, control_pressed = {0.10, 0.27, 0.29, 1},
	control_border = {0.29, 0.34, 0.37, 1}, control_disabled = {0.16, 0.19, 0.21, 1},
	primary = {0.08, 0.29, 0.31, 1}, primary_hover = {0.10, 0.38, 0.39, 1}, primary_pressed = {0.06, 0.23, 0.25, 1},
	primary_border = {0.16, 0.67, 0.64, 1}, on_primary = {0.95, 0.98, 0.98, 1},
	destructive = {0.85, 0.30, 0.30, 1}, destructive_hover = {0.92, 0.36, 0.36, 1}, destructive_pressed = {0.68, 0.20, 0.22, 1},
	destructive_border = {0.85, 0.30, 0.30, 1}, on_destructive = {1, 1, 1, 1},
	focus = {0.16, 0.67, 0.64, 1}, selection = {0.08, 0.29, 0.31, 1}, on_selection = {0.92, 0.97, 0.97, 1}, tab_indicator = {0.16, 0.67, 0.64, 1},
	field = {0.105, 0.12, 0.135, 1}, field_disabled = {0.16, 0.19, 0.21, 1}, placeholder = {0.58, 0.64, 0.68, 1},
	text_selection = {0.08, 0.29, 0.31, 1}, error = {1, 0.43, 0.44, 1},
	checked = {0.16, 0.67, 0.64, 1}, on_checked = {1, 1, 1, 1},
	track = {0.29, 0.34, 0.37, 1}, track_fill = {0.16, 0.67, 0.64, 1},
	thumb = {0.92, 0.94, 0.95, 1}, thumb_border = {0.60, 0.66, 0.69, 1}, thumb_disabled = {0.48, 0.54, 0.58, 1},
	scrollbar = {0.29, 0.34, 0.37, 1}, scrollbar_hover = {0.58, 0.64, 0.68, 1},
	badge_neutral = {0.145, 0.17, 0.19, 1}, badge_neutral_border = {0.38, 0.44, 0.48, 1}, badge_neutral_text = {0.72, 0.77, 0.80, 1},
	badge_success = {0.10, 0.23, 0.20, 1}, badge_success_border = {0.22, 0.49, 0.40, 1}, badge_success_text = {0.40, 0.84, 0.65, 1},
	badge_warning = {0.25, 0.21, 0.13, 1}, badge_warning_border = {0.55, 0.43, 0.22, 1}, badge_warning_text = {0.90, 0.68, 0.25, 1},
	badge_error = {0.27, 0.15, 0.17, 1}, badge_error_border = {0.57, 0.29, 0.32, 1}, badge_error_text = {1, 0.51, 0.53, 1},
	overlay = {0.145, 0.17, 0.19, 1}, overlay_border = {0.29, 0.34, 0.37, 1},
	modal_scrim = {0, 0, 0, 0.48}, shadow_ambient = {0, 0, 0, 0.55}, shadow_contact = {0, 0, 0, 0.45},
}

light :: Color_Scheme{
	background = {0.953, 0.961, 0.965, 1}, surface = {1, 1, 1, 1},
	border = {0.769, 0.804, 0.824, 1}, divider = {0.84, 0.87, 0.88, 1},
	text = {0.125, 0.169, 0.188, 1}, text_muted = {0.349, 0.412, 0.439, 1}, text_disabled = {0.573, 0.616, 0.639, 1},
	control = {0.91, 0.929, 0.937, 1}, control_hover = {0.886, 0.91, 0.918, 1}, control_pressed = {0.835, 0.875, 0.886, 1},
	control_border = {0.70, 0.76, 0.79, 1}, control_disabled = {0.929, 0.941, 0.949, 1},
	primary = {0.031, 0.498, 0.478, 1}, primary_hover = {0.035, 0.51, 0.486, 1}, primary_pressed = {0.024, 0.416, 0.396, 1},
	primary_border = {0.031, 0.498, 0.478, 1}, on_primary = {1, 1, 1, 1},
	destructive = {0.769, 0.247, 0.275, 1}, destructive_hover = {0.80, 0.25, 0.29, 1}, destructive_pressed = {0.65, 0.17, 0.21, 1},
	destructive_border = {0.769, 0.247, 0.275, 1}, on_destructive = {1, 1, 1, 1},
	focus = {0.031, 0.498, 0.478, 1}, selection = {0.867, 0.945, 0.933, 1}, on_selection = {0.02, 0.31, 0.30, 1}, tab_indicator = {0.031, 0.498, 0.478, 1},
	field = {1, 1, 1, 1}, field_disabled = {0.929, 0.941, 0.949, 1}, placeholder = {0.349, 0.412, 0.439, 1},
	text_selection = {0.72, 0.88, 0.85, 1}, error = {0.72, 0.16, 0.21, 1},
	checked = {0.031, 0.498, 0.478, 1}, on_checked = {1, 1, 1, 1},
	track = {0.82, 0.86, 0.88, 1}, track_fill = {0.031, 0.498, 0.478, 1},
	thumb = {1, 1, 1, 1}, thumb_border = {0.59, 0.65, 0.68, 1}, thumb_disabled = {0.76, 0.80, 0.82, 1},
	scrollbar = {0.69, 0.75, 0.78, 1}, scrollbar_hover = {0.45, 0.53, 0.57, 1},
	badge_neutral = {0.94, 0.95, 0.96, 1}, badge_neutral_border = {0.79, 0.83, 0.85, 1}, badge_neutral_text = {0.35, 0.41, 0.44, 1},
	badge_success = {0.90, 0.97, 0.94, 1}, badge_success_border = {0.67, 0.85, 0.76, 1}, badge_success_text = {0.07, 0.40, 0.27, 1},
	badge_warning = {1, 0.96, 0.86, 1}, badge_warning_border = {0.91, 0.78, 0.49, 1}, badge_warning_text = {0.51, 0.31, 0.04, 1},
	badge_error = {1, 0.92, 0.93, 1}, badge_error_border = {0.91, 0.72, 0.75, 1}, badge_error_text = {0.65, 0.17, 0.21, 1},
	overlay = {1, 1, 1, 1}, overlay_border = {0.769, 0.804, 0.824, 1},
	modal_scrim = {0.12, 0.16, 0.19, 0.24}, shadow_ambient = {0.08, 0.13, 0.16, 0.14}, shadow_contact = {0.08, 0.13, 0.16, 0.18},
}

// Active configuration for subsequent widget calls. Reset with begin for each
// window update. Assign directly to switch midway; save/restore for a subtree.
colors: Color_Scheme = dark
