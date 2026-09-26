package platform

import ns "core:sys/darwin/Foundation"
import mtl "vendor:darwin/Metal"
import "../core/primitives"

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
	// Never reuse ids: copies of a released handle cannot select a later image.
	renderer.next_image_id += 1
	assert(renderer.next_image_id != 0, "Image id overflow")
	renderer.images[renderer.next_image_id] = texture
	return {id = renderer.next_image_id, size = size}, .None
}

@(private)
destroy_image_impl :: proc(handle: Renderer, image: primitives.Image) {
	renderer := cast(^Metal_Renderer)handle
	if texture, ok := renderer.images[image.id]; ok {
		delete_key(&renderer.images, image.id)
		texture->release()
	}
}
