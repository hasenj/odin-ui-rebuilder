package primitives

// An immutable image resource belonging to one window's renderer.
// A zero id means no image. Copying this value does not duplicate the texture.
Image :: struct {
	id:   u64,
	size: [2]int, // Original dimensions in pixels.
}
