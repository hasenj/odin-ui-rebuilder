// Shared rendering data; this package has no platform dependencies.
package primitives

// Straight (not premultiplied) RGBA components in the range 0..1.
Color :: [4]f32

// Window-relative, half-open rectangle. An enabled empty clip draws nothing.
Clip :: struct {enabled: bool, min, max: [2]f32}

// Coordinates are logical points, with the origin at the top left and Y down.
// Surfaces draw in slice order, with later surfaces on top.
Surface :: struct {
	position:      [2]f32,
	size:          [2]f32,
	background:    Color,
	corner_radius: f32,
	// Gaussian standard deviation in logical points; >0 draws a shadow mask.
	shadow_sigma: f32,
	// Inward outline thickness; zero draws a filled surface.
	border_width: f32,
	// Optional image stretched over this surface. background becomes a tint;
	// use opaque white for the original image colors. Corners clip the image.
	image:         Image,
	// Normalized UV min/max; zero means the entire image.
	image_region:  [4]f32,
	clip: Clip,
}
