package platform

import "base:runtime"
import "base:intrinsics"
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
	window_handle: Window,
	window: ^ns.Window,
	delegate: ns.id,
	device:        ^mtl.Device,
	queue:         ^mtl.CommandQueue,
	pipeline:      ^mtl.RenderPipelineState,
	white_texture: ^mtl.Texture,
	images:        [dynamic]Image_Slot,
	free_image:    u32,
	view:          ^mtk.View,
	frame:         Frame_Proc,
	user_data:     rawptr,
	input_state:   ^input.State,
	pending_scroll: [2]f32,
	keyboard: Keyboard_Input,
	start:         time.Tick,
	odin_context:  runtime.Context,
	profiler:      Frame_Profiler,
	drawing:       bool,
	resize_pending: bool,
	capture_scale: f32, // Used only when there is no native view.
}

// Explicit padding keeps the array stride identical to the Metal struct.
@(private)
GPU_Surface :: struct {
	position: [2]f32,
	size:     [2]f32,
	color:    [4]f32,
	radius:   f32,
	_padding: [3]f32,
	uv: [4]f32,
	clip: [4]f32,
}

#assert(size_of(GPU_Surface) == 80)
#assert(offset_of(GPU_Surface, color) == 16)
#assert(offset_of(GPU_Surface, radius) == 32)

@(private)
metal_init :: proc(renderer: ^Metal_Renderer) {
	renderer.device = mtl.CreateSystemDefaultDevice()
	assert(renderer.device != nil, "No Metal-capable GPU is available")
	renderer.queue = renderer.device->newCommandQueue()
	assert(renderer.queue != nil, "Could not create the Metal command queue")

	// Embedded at build time: the executable can run from any directory.
	source := ns.String.alloc()->initWithOdinString(#load("surfaces.metal"))
	defer source->release()
	library, library_error := renderer.device->newLibraryWithSource(source, nil)
	if library == nil {
		metal_fail("Could not compile surface shaders", library_error)
	}
	defer library->release()
	vertex_name := ns.String.alloc()->initWithOdinString("surface_vertex")
	fragment_name := ns.String.alloc()->initWithOdinString("surface_fragment")
	defer vertex_name->release()
	defer fragment_name->release()
	vertex := library->newFunctionWithName(vertex_name)
	fragment := library->newFunctionWithName(fragment_name)
	assert(vertex != nil && fragment != nil, "Surface shader entry points are missing")
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
		metal_fail("Could not create the surface pipeline", pipeline_error)
	}
	renderer.pipeline = pipeline
	renderer.images = make([dynamic]Image_Slot)
	white := [4]u8{255, 255, 255, 255}
	renderer.white_texture = upload_texture(renderer.device, white[:], {1, 1})
	assert(renderer.white_texture != nil, "Could not create the solid-color texture")
}

@(private)
metal_destroy :: proc(renderer: ^Metal_Renderer) {
	for slot in renderer.images {
		if slot.texture != nil {
			slot.texture->release()
		}
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
render_impl :: proc(handle: Renderer, surfaces: []primitives.Surface, size: [2]f32, timing: ^Render_Timing) {
	renderer := cast(^Metal_Renderer)handle
	if size.x <= 0 || size.y <= 0 {
		return
	}
	// MetalKit can acquire (and wait for) a drawable through either accessor.
	wait_start := render_wait_begin(timing)
	pass := renderer.view->currentRenderPassDescriptor()
	render_wait_end(timing, wait_start)
	// A drawable can be unavailable while minimized or during a resize.
	if pass == nil {
		return
	}
	wait_start = render_wait_begin(timing)
	drawable := renderer.view->currentDrawable()
	render_wait_end(timing, wait_start)
	if drawable == nil {
		return
	}
	// A resize must present with the window's Core Animation transaction;
	// otherwise the compositor can stretch the old frame to the new bounds.
	// Keep ordinary animation on the asynchronous presentation path.
	resize_present := renderer.resize_pending || bool(intrinsics.objc_send(ns.BOOL, renderer.view, "inLiveResize"))
	renderer.view->setPresentsWithTransaction(resize_present)
	command := renderer.queue->commandBuffer()
	assert(command != nil, "Could not create a Metal command buffer")
	encoder := command->renderCommandEncoderWithDescriptor(pass)
	assert(encoder != nil, "Could not create a Metal render encoder")
	encode_surfaces(renderer, encoder, surfaces, size)
	encoder->endEncoding()
	if resize_present {
		// https://developer.apple.com/documentation/quartzcore/cametallayer/presentswithtransaction
		// Transaction presentation requires commit -> scheduled -> drawable present,
		// not CommandBuffer.presentDrawable. No wait for GPU completion is needed.
		command->commit()
		wait_start = render_wait_begin(timing)
		command->waitUntilScheduled()
		drawable->present()
		render_wait_end(timing, wait_start)
	} else {
		command->presentDrawable(drawable)
		command->commit()
	}
	renderer.resize_pending = false
}

@(private)
encode_surfaces :: proc(renderer: ^Metal_Renderer, encoder: ^mtl.RenderCommandEncoder, surfaces: []primitives.Surface, size: [2]f32) {
	encoder->setRenderPipelineState(renderer.pipeline)
	viewport := size
	encoder->setVertexBytes(mem.ptr_to_bytes(&viewport), 1)

	// setVertexBytes copies each batch into Metal-owned storage, so the CPU can
	// reuse this memory immediately without racing an in-flight GPU frame.
	// 48 * 80 bytes stays below Metal's 4 KiB inline-data limit.
	batch: [48]GPU_Surface
	count := 0
	batch_texture: ^mtl.Texture
	for surface in surfaces {
		if surface.size.x <= 0 || surface.size.y <= 0 {
			continue
		}
		texture := renderer.white_texture
		if surface.image != (primitives.Image{}) {
			slot := lookup_image(renderer, surface.image)
			if slot == nil {
				continue // Released or invalid image handle.
			}
			texture = slot.texture
		}
		// Only batch adjacent primitives with the same texture, preserving the
		// original draw order across solid surfaces and overlapping images.
		if count > 0 && texture != batch_texture {
			encoder->setFragmentTexture(batch_texture, 0)
			encoder->setVertexBytes(mem.slice_to_bytes(batch[:count]), 0)
			encoder->drawPrimitivesWithInstanceCount(.TriangleStrip, 0, 4, ns.UInteger(count))
			count = 0
		}
		batch_texture = texture
		batch[count] = {
			position = surface.position,
			size = surface.size,
			color = surface.background,
			radius = clamp(surface.corner_radius, 0, min(surface.size.x, surface.size.y) * 0.5),
			uv = surface.image_region if surface.image_region != ([4]f32{}) else [4]f32{0, 0, 1, 1},
			clip = {surface.clip.min.x, surface.clip.min.y, surface.clip.max.x, surface.clip.max.y} if surface.clip.enabled else [4]f32{-max(f32), -max(f32), max(f32), max(f32)},
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

@(private)
pixel_scale_impl :: proc(handle: Renderer) -> f32 {
	view := (cast(^Metal_Renderer)handle).view
	if view == nil {
		scale := (cast(^Metal_Renderer)handle).capture_scale
		return scale if scale > 0 else 1
	}
	window := intrinsics.objc_send(^ns.Window, view, "window")
	return f32(window->backingScaleFactor()) if window != nil else 1
}
