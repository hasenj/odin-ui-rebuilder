package platform

import "core:c"
import "core:math"
import "core:mem"
import "core:os"
import ns "core:sys/darwin/Foundation"
import mtl "vendor:darwin/Metal"
import stb "vendor:stb/image"
import "../core/input"
import "../core/primitives"

@(private)
capture_frames_impl :: proc(frames: []Capture_Frame, frame: Frame_Proc, user_data: rawptr, input_state: ^input.State) -> Capture_Result {
	ns.scoped_autoreleasepool()
	// Own temporary storage: capture must not reset the caller's scratch arena.
	temporary: mem.Dynamic_Arena
	mem.dynamic_arena_init(&temporary)
	defer mem.dynamic_arena_destroy(&temporary)
	context.temp_allocator = mem.dynamic_arena_allocator(&temporary)
	renderer: Metal_Renderer
	metal_init(&renderer)
	defer metal_destroy(&renderer)
	for item, i in frames {
		err := capture_one_frame(&renderer, item, frame, user_data, input_state)
		if err != .None { return {err, i} }
	}
	return {frame_index = -1}
}

@(private)
capture_one_frame :: proc(renderer: ^Metal_Renderer, item: Capture_Frame, frame: Frame_Proc, user_data: rawptr, input_state: ^input.State) -> Capture_Error {
	ns.scoped_autoreleasepool()
	// Match the window loop: temporary builder data lives through submission.
	defer free_all(context.temp_allocator)
	renderer.capture_scale = item.scale
	if input_state != nil { input_state^ = item.input }
	surfaces: []primitives.Surface
	if frame != nil { surfaces = frame(Renderer(renderer), item.time, item.size, user_data) }
	if item.path == "" { return .None }
	width := int(math.ceil(f64(item.size.x) * f64(item.scale)))
	height := int(math.ceil(f64(item.size.y) * f64(item.scale)))
	descriptor := mtl.TextureDescriptor.texture2DDescriptorWithPixelFormat(.BGRA8Unorm, ns.UInteger(width), ns.UInteger(height), false)
	descriptor->setUsage({.RenderTarget})
	descriptor->setStorageMode(.Shared)
	texture := renderer.device->newTextureWithDescriptor(descriptor)
	if texture == nil { return .Render_Failed }
	defer texture->release()
	pass := mtl.RenderPassDescriptor.renderPassDescriptor()
	attachment := pass->colorAttachments()->object(0)
	attachment->setTexture(texture)
	attachment->setLoadAction(.Clear)
	attachment->setStoreAction(.Store)
	color := item.clear_color
	attachment->setClearColor({f64(color.r * color.a), f64(color.g * color.a), f64(color.b * color.a), f64(color.a)})
	command := renderer.queue->commandBuffer()
	if command == nil { return .Render_Failed }
	encoder := command->renderCommandEncoderWithDescriptor(pass)
	if encoder == nil { return .Render_Failed }
	encode_surfaces(renderer, encoder, surfaces, item.size)
	encoder->endEncoding()
	command->commit()
	command->waitUntilCompleted()
	if command->status() != .Completed { return .Render_Failed }
	pixels := make([][4]u8, width * height)
	defer delete(pixels)
	texture->getBytes(raw_data(pixels), ns.UInteger(width * 4), {size = {ns.Integer(width), ns.Integer(height), 1}}, 0)
	// Metal produces top-down premultiplied BGRA; PNG requires straight RGBA.
	// Unpremultiply exactly once so translucent panels retain their brightness.
	for &pixel in pixels {
		alpha := u32(pixel[3])
		if alpha == 0 { pixel = {}; continue }
		red := pixel[2]
		pixel[2] = u8(min(255, (u32(pixel[0]) * 255 + alpha / 2) / alpha))
		pixel[1] = u8(min(255, (u32(pixel[1]) * 255 + alpha / 2) / alpha))
		pixel[0] = u8(min(255, (u32(red) * 255 + alpha / 2) / alpha))
	}
	// Encode into memory first so Odin's file API reports write failures too.
	output := PNG_Output{odin_context = context}
	defer delete(output.bytes)
	if stb.write_png_to_func(png_write, &output, c.int(width), c.int(height), 4, raw_data(pixels), c.int(width * 4)) == 0 {
		return .Write_Failed
	}
	if os.write_entire_file(item.path, output.bytes[:]) != nil { return .Write_Failed }
	return .None
}

