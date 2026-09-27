package ui

import "core:math"
import "core:math/linalg"

// Emit a surface immediately, without consuming space or creating layout state.
// Later cuts/padding do not change it. Images stretch over this rect; white tint
// preserves their colors. Corners affect only this surface, not child paint.
paint :: proc(color: Color = {1, 1, 1, 1}, img: Image = {}, corners: f32 = 0) {
	assert(valid_length(corners), "Corner radius must be finite and nonnegative")
	r := current_rect()
	append(&active_state.frame.surfaces, Surface{
		position = r.position, size = r.size,
		background = color, image = img, corner_radius = corners,
	})
}

// Hue is in degrees (wrapped); saturation/lightness are percentages (clamped).
// Alpha uses the usual 0..1 range. Returns straight RGBA, like Color literals.
hsl :: proc(hue, saturation, lightness: f32, alpha: f32 = 1) -> Color {
	assert(abs(hue) <= max(f32) && abs(saturation) <= max(f32) && abs(lightness) <= max(f32) && abs(alpha) <= max(f32), "HSL components must be finite")
	h := hue / 360
	h -= math.floor(h)
	return Color(linalg.vector4_hsl_to_rgb_f32(h, clamp(saturation, 0, 100) / 100, clamp(lightness, 0, 100) / 100, clamp(alpha, 0, 1)))
}
