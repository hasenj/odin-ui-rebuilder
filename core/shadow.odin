package ui

// A shadow is a separate paint operation, before its casting surface. Blur is
// Gaussian sigma in logical points; the GPU quad extends 3 sigma beyond the
// spread bounds. It never creates an identity or changes layout/hit geometry.
// Rectangular shadows are analytic; rounded shadows use fixed-cost quadrature.
shadow :: proc(color: Color = {0, 0, 0, 0.45}, offset: [2]f32 = {0, 4}, blur: f32 = 8, spread: f32 = 0, corners: f32 = 4) {
	assert(valid_length(blur) && valid_length(corners) && abs(spread) <= max(f32))
	assert(abs(offset.x) <= max(f32) && abs(offset.y) <= max(f32))
	r := current_rect() // Requires resolved geometry, like other low-level paint.
	r.position += offset - [2]f32{spread, spread}
	r.size += [2]f32{2*spread, 2*spread}
	if r.size.x <= 0 || r.size.y <= 0 { return }
	append(&current_frame().surfaces, Surface{position = r.position, size = r.size,
		background = color, corner_radius = max(0, corners + spread), shadow_sigma = blur})
}

// Stroke is entirely inside the current rect and preserves its transparent
// interior. Like shadow, it requires a resolved rect and respects active clips.
stroke :: proc(color: Color, width: f32 = 1, corners: f32 = 0) {
	assert(valid_length(width) && valid_length(corners))
	if width == 0 { return }
	r := current_rect()
	append(&current_frame().surfaces, Surface{position = r.position, size = r.size,
		background = color, corner_radius = corners, border_width = width})
}
