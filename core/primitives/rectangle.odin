// Shared rendering data; this package has no platform dependencies.
package primitives

// Straight (not premultiplied) RGBA components in the range 0..1.
Color :: [4]f32

// Coordinates are logical points, with the origin at the top left and Y down.
// Rectangles draw in slice order, with later rectangles on top.
Rectangle :: struct {
	position:      [2]f32,
	size:          [2]f32,
	background:    Color,
	corner_radius: f32,
}
