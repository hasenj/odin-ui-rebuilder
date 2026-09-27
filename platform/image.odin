package platform

import "../core/primitives"

Image_Error :: enum {
	None,
	Invalid_Renderer,
	Invalid_Pixels,
	Invalid_Image,
	Too_Large,
	Texture_Creation_Failed,
}

// Upload top-to-bottom, premultiplied RGBA8 pixels. The data is copied
// before this returns. Call on the main thread with the active window's renderer.
create_image :: proc(renderer: Renderer, pixels: []u8, size: [2]int) -> (primitives.Image, Image_Error) {
	if renderer == nil {
		return {}, .Invalid_Renderer
	}
	if size.x <= 0 || size.y <= 0 {
		return {}, .Invalid_Pixels
	}
	// Shared upper limit; the backend also checks any lower device limit.
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

// Internal atlas upload: tightly packed premultiplied RGBA8, ordered before
// subsequent draws and after previously submitted draws. CPU data is copied.
update_image :: proc(renderer: Renderer, image: primitives.Image, pixels: []u8, position, size: [2]int) -> Image_Error {
	image_extent, ok := image_size(renderer, image)
	if !ok {
		return .Invalid_Image
	}
	if position.x < 0 || position.y < 0 || size.x <= 0 || size.y <= 0 ||
	   size.x > image_extent.x || size.y > image_extent.y ||
	   position.x > image_extent.x - size.x || position.y > image_extent.y - size.y ||
	   len(pixels) != size.x * size.y * 4 {
		return .Invalid_Pixels
	}
	return update_image_impl(renderer, image, pixels, position, size)
}
