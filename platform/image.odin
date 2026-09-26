package platform

import "../core/primitives"

Image_Error :: enum {
	None,
	Invalid_Renderer,
	Invalid_Pixels,
	Too_Large,
	Texture_Creation_Failed,
}

// Upload immutable, top-to-bottom, premultiplied RGBA8 pixels. The data is copied
// before this returns. Call on the main thread with the active window's renderer.
create_image :: proc(renderer: Renderer, pixels: []u8, size: [2]int) -> (primitives.Image, Image_Error) {
	if renderer == nil {
		return {}, .Invalid_Renderer
	}
	if size.x <= 0 || size.y <= 0 {
		return {}, .Invalid_Pixels
	}
	// All supported desktop Metal GPU families allow at least 16384 per axis.
	if size.x > 16384 || size.y > 16384 {
		return {}, .Too_Large
	}
	if len(pixels) != size.x * size.y * 4 {
		return {}, .Invalid_Pixels
	}
	return create_image_impl(renderer, pixels, size)
}

destroy_image :: proc(renderer: Renderer, image: primitives.Image) {
	if renderer != nil {
		destroy_image_impl(renderer, image)
	}
}

// Original dimensions in pixels; handles must belong to this renderer.
image_size :: proc(renderer: Renderer, image: primitives.Image) -> (size: [2]int, ok: bool) {
	if renderer == nil {
		return {}, false
	}
	return image_size_impl(renderer, image)
}
