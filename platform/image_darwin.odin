package platform

import ns "core:sys/darwin/Foundation"
import mtl "vendor:darwin/Metal"
import "../core/primitives"

@(private)
Image_Slot :: struct {
	texture:    ^mtl.Texture,
	size:       [2]int,
	generation: u32,
	next_free:  u32, // One-based index; zero ends the free list.
}

// Do not retain this pointer across image creation: appending can move the array.
@(private)
lookup_image :: proc(renderer: ^Metal_Renderer, image: primitives.Image) -> ^Image_Slot {
	if image.index == 0 || int(image.index) > len(renderer.images) {
		return nil
	}
	slot := &renderer.images[image.index - 1]
	if slot.texture == nil || slot.generation != image.generation {
		return nil
	}
	return slot
}

@(private)
upload_texture :: proc(device: ^mtl.Device, pixels: []u8, size: [2]int) -> ^mtl.Texture {
	ns.scoped_autoreleasepool()
	descriptor := mtl.TextureDescriptor.texture2DDescriptorWithPixelFormat(.RGBA8Unorm, ns.UInteger(size.x), ns.UInteger(size.y), false)
	descriptor->setUsage({.ShaderRead})
	descriptor->setStorageMode(.Shared)
	texture := device->newTextureWithDescriptor(descriptor)
	if texture != nil {
		texture->replaceRegion({size = {ns.Integer(size.x), ns.Integer(size.y), 1}}, 0, raw_data(pixels), ns.UInteger(size.x * 4))
	}
	return texture
}

@(private)
create_image_impl :: proc(handle: Renderer, pixels: []u8, size: [2]int) -> (primitives.Image, Image_Error) {
	renderer := cast(^Metal_Renderer)handle
	texture := upload_texture(renderer.device, pixels, size)
	if texture == nil {
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
	renderer := cast(^Metal_Renderer)handle
	slot := lookup_image(renderer, image)
	if slot == nil {
		return
	}
	slot.texture->release()
	slot.texture = nil
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
	if slot := lookup_image(cast(^Metal_Renderer)handle, image); slot != nil {
		return slot.size, true
	}
	return {}, false
}

@(private)
update_image_impl :: proc(handle: Renderer, image: primitives.Image, pixels: []u8, position, size: [2]int) -> Image_Error {
	renderer := cast(^Metal_Renderer)handle
	slot := lookup_image(renderer, image)
	// Stage into a fresh texture; never CPU-write an atlas still read by the GPU.
	staging := upload_texture(renderer.device, pixels, size)
	if staging == nil {
		return .Texture_Creation_Failed
	}
	defer staging->release()
	command := renderer.queue->commandBuffer()
	encoder := command->blitCommandEncoder()
	encoder->copyFromTextureWithDestinationOrigin(staging, 0, 0, {},
		{ns.Integer(size.x), ns.Integer(size.y), 1}, slot.texture, 0, 0,
		{ns.Integer(position.x), ns.Integer(position.y), 0})
	encoder->endEncoding()
	command->commit()
	return .None
}
