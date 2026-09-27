package platform

import gl "vendor:OpenGL"
import "../core/primitives"

@(private)
Image_Slot :: struct {
	texture:    u32,
	size:       [2]int,
	generation: u32,
	next_free:  u32, // One-based index; zero ends the free list.
}

// Do not retain this pointer across image creation: appending can move the array.
@(private)
lookup_image :: proc(renderer: ^GL_Renderer, image: primitives.Image) -> ^Image_Slot {
	if image.index == 0 || int(image.index) > len(renderer.images) {
		return nil
	}
	slot := &renderer.images[image.index - 1]
	if slot.texture == 0 || slot.generation != image.generation {
		return nil
	}
	return slot
}

@(private)
upload_texture :: proc(pixels: []u8, size: [2]int) -> u32 {
	texture: u32
	gl.GenTextures(1, &texture)
	gl.BindTexture(gl.TEXTURE_2D, texture)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, i32(size.x), i32(size.y), 0, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))
	if gl.GetError() != gl.NO_ERROR {
		gl.DeleteTextures(1, &texture)
		return 0
	}
	return texture
}

@(private)
create_image_impl :: proc(handle: Renderer, pixels: []u8, size: [2]int) -> (primitives.Image, Image_Error) {
	renderer := cast(^GL_Renderer)handle
	if size.x > int(renderer.max_texture_size) || size.y > int(renderer.max_texture_size) {
		return {}, .Too_Large
	}
	texture := upload_texture(pixels, size)
	if texture == 0 {
		return {}, .Texture_Creation_Failed
	}
	index := renderer.free_image
	if index != 0 {
		slot := &renderer.images[index - 1]
		renderer.free_image = slot.next_free
		slot.texture = texture
		slot.size = size
		slot.next_free = 0
	} else {
		assert(len(renderer.images) < int(max(u32)), "Image slot limit reached")
		append(&renderer.images, Image_Slot{texture = texture, size = size, generation = 1})
		index = u32(len(renderer.images))
	}
	return {index = index, generation = renderer.images[index - 1].generation}, .None
}

@(private)
destroy_image_impl :: proc(handle: Renderer, image: primitives.Image) {
	renderer := cast(^GL_Renderer)handle
	slot := lookup_image(renderer, image)
	if slot == nil {
		return
	}
	gl.DeleteTextures(1, &slot.texture)
	slot.texture = 0
	slot.size = {}
	// Retire an exhausted slot instead of wrapping and reviving stale handles.
	if slot.generation != max(u32) {
		slot.generation += 1
		slot.next_free = renderer.free_image
		renderer.free_image = image.index
	}
}

@(private)
image_size_impl :: proc(handle: Renderer, image: primitives.Image) -> (size: [2]int, ok: bool) {
	if slot := lookup_image(cast(^GL_Renderer)handle, image); slot != nil {
		return slot.size, true
	}
	return {}, false
}

@(private)
update_image_impl :: proc(handle: Renderer, image: primitives.Image, pixels: []u8, position, size: [2]int) -> Image_Error {
	slot := lookup_image(cast(^GL_Renderer)handle, image)
	gl.BindTexture(gl.TEXTURE_2D, slot.texture)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.TexSubImage2D(gl.TEXTURE_2D, 0, i32(position.x), i32(position.y), i32(size.x), i32(size.y), gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))
	return .None if gl.GetError() == gl.NO_ERROR else .Texture_Creation_Failed
}
