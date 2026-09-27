package primitives

// An image resource belonging to one window's renderer.
// The zero value means no image. Copying this value does not duplicate the texture.
// Index is one-based; generation prevents released handles from selecting a
// new image when their slot is reused. Handles are local to their renderer.
Image :: struct {
	index:      u32,
	generation: u32,
}
