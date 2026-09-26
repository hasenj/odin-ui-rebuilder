package platform

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:time"
import ns "core:sys/darwin/Foundation"
import mtl "vendor:darwin/Metal"
import mtk "vendor:darwin/MetalKit"
import "../core/primitives"
import "../core/input"

@(private)
Metal_Renderer :: struct {
	device:        ^mtl.Device,
	queue:         ^mtl.CommandQueue,
	pipeline:      ^mtl.RenderPipelineState,
	white_texture: ^mtl.Texture,
	images:        map[u64]^mtl.Texture,
	next_image_id:  u64,
	view:          ^mtk.View,
	frame:         Frame_Proc,
	user_data:     rawptr,
	input_state:   ^input.State,
	start:         time.Tick,
	odin_context:  runtime.Context,
	profiler:      Frame_Profiler,
}

// Explicit padding keeps the array stride identical to the Metal struct.
@(private)
GPU_Rectangle :: struct {
	position: [2]f32,
	size:     [2]f32,
	color:    [4]f32,
	radius:   f32,
	_padding: [3]f32,
}

#assert(size_of(GPU_Rectangle) == 48)
#assert(offset_of(GPU_Rectangle, color) == 16)
#assert(offset_of(GPU_Rectangle, radius) == 32)

@(private)
metal_init :: proc(renderer: ^Metal_Renderer) {
	renderer.device = mtl.CreateSystemDefaultDevice()
	assert(renderer.device != nil, "No Metal-capable GPU is available")
	renderer.queue = renderer.device->newCommandQueue()
	assert(renderer.queue != nil, "Could not create the Metal command queue")

	// Embedded at build time: the executable can run from any directory.
	source := ns.String.alloc()->initWithOdinString(#load("rectangles.metal"))
	defer source->release()
	library, library_error := renderer.device->newLibraryWithSource(source, nil)
	if library == nil {
		metal_fail("Could not compile rectangle shaders", library_error)
	}
	defer library->release()
	vertex_name := ns.String.alloc()->initWithOdinString("rectangle_vertex")
	fragment_name := ns.String.alloc()->initWithOdinString("rectangle_fragment")
	defer vertex_name->release()
	defer fragment_name->release()
	vertex := library->newFunctionWithName(vertex_name)
	fragment := library->newFunctionWithName(fragment_name)
	assert(vertex != nil && fragment != nil, "Rectangle shader entry points are missing")
	defer vertex->release()
	defer fragment->release()

	descriptor := mtl.RenderPipelineDescriptor.alloc()->init()
	defer descriptor->release()
	descriptor->setVertexFunction(vertex)
	descriptor->setFragmentFunction(fragment)
	attachment := descriptor->colorAttachments()->object(0)
	attachment->setPixelFormat(.BGRA8Unorm)
	attachment->setBlendingEnabled(true)
	attachment->setSourceRGBBlendFactor(.One)
	attachment->setDestinationRGBBlendFactor(.OneMinusSourceAlpha)
	attachment->setSourceAlphaBlendFactor(.One)
	attachment->setDestinationAlphaBlendFactor(.OneMinusSourceAlpha)
	pipeline, pipeline_error := renderer.device->newRenderPipelineStateWithDescriptor(descriptor)
	if pipeline == nil {
		metal_fail("Could not create the rectangle pipeline", pipeline_error)
	}
	renderer.pipeline = pipeline
	renderer.images = make(map[u64]^mtl.Texture)
	white := [4]u8{255, 255, 255, 255}
	renderer.white_texture = upload_texture(renderer.device, white[:], {1, 1})
	assert(renderer.white_texture != nil, "Could not create the solid-color texture")
}

@(private)
metal_destroy :: proc(renderer: ^Metal_Renderer) {
	for _, texture in renderer.images {
		texture->release()
	}
	delete(renderer.images)
	renderer.white_texture->release()
	renderer.pipeline->release()
	renderer.queue->release()
	renderer.device->release()
}

@(private)
metal_fail :: proc(message: string, error: ^ns.Error) {
	if error != nil {
		fmt.eprintln(message, string(error->localizedDescription()->UTF8String()))
	}
	panic(message)
}

@(private)
render_impl :: proc(handle: Renderer, rectangles: []primitives.Rectangle, size: [2]f32) {
	renderer := cast(^Metal_Renderer)handle
	if size.x <= 0 || size.y <= 0 {
		return
	}
	pass := renderer.view->currentRenderPassDescriptor()
	// A drawable can be unavailable while minimized or during a resize.
	if pass == nil {
		return
	}
	drawable := renderer.view->currentDrawable()
	if drawable == nil {
		return
	}
	command := renderer.queue->commandBuffer()
	assert(command != nil, "Could not create a Metal command buffer")
	encoder := command->renderCommandEncoderWithDescriptor(pass)
	assert(encoder != nil, "Could not create a Metal render encoder")
	encode_rectangles(renderer, encoder, rectangles, size)
	encoder->endEncoding()
	command->presentDrawable(drawable)
	command->commit()
}

@(private)
encode_rectangles :: proc(renderer: ^Metal_Renderer, encoder: ^mtl.RenderCommandEncoder, rectangles: []primitives.Rectangle, size: [2]f32) {
	encoder->setRenderPipelineState(renderer.pipeline)
	viewport := size
	encoder->setVertexBytes(mem.ptr_to_bytes(&viewport), 1)

	// setVertexBytes copies each batch into Metal-owned storage, so the CPU can
	// reuse this memory immediately without racing an in-flight GPU frame.
	// 64 * 48 bytes stays below Metal's 4 KiB inline-data limit.
	batch: [64]GPU_Rectangle
	count := 0
	batch_texture: ^mtl.Texture
	for rectangle in rectangles {
		if rectangle.size.x <= 0 || rectangle.size.y <= 0 {
			continue
		}
		texture := renderer.white_texture
		if rectangle.image.id != 0 {
			texture = renderer.images[rectangle.image.id]
			if texture == nil {
				continue // Released or invalid image handle.
			}
		}
		// Only batch adjacent primitives with the same texture, preserving the
		// original draw order across solid rectangles and overlapping images.
		if count > 0 && texture != batch_texture {
			encoder->setFragmentTexture(batch_texture, 0)
			encoder->setVertexBytes(mem.slice_to_bytes(batch[:count]), 0)
			encoder->drawPrimitivesWithInstanceCount(.TriangleStrip, 0, 4, ns.UInteger(count))
			count = 0
		}
		batch_texture = texture
		batch[count] = {
			position = rectangle.position,
			size = rectangle.size,
			color = rectangle.background,
			radius = clamp(rectangle.corner_radius, 0, min(rectangle.size.x, rectangle.size.y) * 0.5),
		}
		for &component in batch[count].color {
			component = clamp(component, 0, 1)
		}
		count += 1
		if count == len(batch) {
			encoder->setFragmentTexture(batch_texture, 0)
			encoder->setVertexBytes(mem.slice_to_bytes(batch[:count]), 0)
			encoder->drawPrimitivesWithInstanceCount(.TriangleStrip, 0, 4, ns.UInteger(count))
			count = 0
		}
	}
	if count > 0 {
		encoder->setFragmentTexture(batch_texture, 0)
		encoder->setVertexBytes(mem.slice_to_bytes(batch[:count]), 0)
		encoder->drawPrimitivesWithInstanceCount(.TriangleStrip, 0, 4, ns.UInteger(count))
	}
}
