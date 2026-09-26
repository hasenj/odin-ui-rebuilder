#+build darwin
package platform

import "core:testing"
import ns "core:sys/darwin/Foundation"
import mtl "vendor:darwin/Metal"
import "../core/primitives"

// Runs the actual shader and blend pipeline, then reads GPU output back.
// Run on a Mac with a Metal GPU: odin test platform -out:bin/platform-tests
@(test)
metal_rectangle_rendering :: proc(t: ^testing.T) {
	ns.scoped_autoreleasepool()
	renderer: Metal_Renderer
	metal_init(&renderer)
	defer metal_destroy(&renderer)
	texture := test_texture(renderer.device, 128, 96)
	defer texture->release()
	pixels: [128 * 96][4]u8
	scene := [?]primitives.Rectangle{
		{position = {8, 8}, size = {40, 40}, background = {1, 0, 0, 1}, corner_radius = 16},
		{position = {28, 24}, size = {32, 24}, background = {0, 0, 1, 0.5}},
		{position = {70, 8}, size = {24, 30}, background = {0, 1, 0, 1}},
		{position = {-10, 70}, size = {25, 20}, background = {1, 1, 0, 1}},
		{position = {70, 60}, size = {24, 24}, background = {1, 0, 1, 1}, corner_radius = 100},
	}
	test_render(t, &renderer, texture, scene[:], {128, 96}, raw_data(pixels[:]))
	expect_pixel(t, pixels[20 * 128 + 28], {0, 0, 255, 255}) // Red center.
	expect_pixel(t, pixels[9 * 128 + 9], {}) // Rounded corner is outside.
	expect_pixel(t, pixels[8 * 128 + 70], {0, 255, 0, 255}) // Square corner.
	expect_pixel(t, pixels[30 * 128 + 32], {128, 0, 127, 255}) // Source-over, list order.
	expect_pixel(t, pixels[30 * 128 + 56], {128, 0, 0, 128}) // Premultiplied transparency.
	expect_pixel(t, pixels[75 * 128 + 0], {0, 255, 255, 255}) // Clipped left edge.
	expect_pixel(t, pixels[61 * 128 + 71], {}) // Oversized radius clamps to a circle.
	expect_pixel(t, pixels[72 * 128 + 82], {255, 0, 255, 255})
	coverage := pixels[12 * 128 + 12][3]
	testing.expect(t, coverage > 0 && coverage < 255, "Rounded edges must have partial pixel coverage")

	// The same render target must not retain anything from the previous list.
	test_render(t, &renderer, texture, nil, {128, 96}, raw_data(pixels[:]))
	for pixel in pixels {
		if !testing.expect_value(t, pixel, [4]u8{}) {
			break
		}
	}

	// More than two inline batches, including a skipped degenerate rectangle.
	batch_scene: [131]primitives.Rectangle
	for &rectangle in batch_scene {
		rectangle = {position = {8, 8}, size = {40, 40}, background = {1, 0, 0, 1}}
	}
	batch_scene[64].size = {0, 40}
	batch_scene[130].background = {0, 1, 0, 1}
	test_render(t, &renderer, texture, batch_scene[:], {128, 96}, raw_data(pixels[:]))
	expect_pixel(t, pixels[20 * 128 + 20], {0, 255, 0, 255})

	// A Retina-sized drawable preserves logical point coordinates.
	retina := test_texture(renderer.device, 256, 192)
	defer retina->release()
	retina_pixels := make([][4]u8, 256 * 192)
	defer delete(retina_pixels)
	test_render(t, &renderer, retina, scene[:], {128, 96}, raw_data(retina_pixels))
	expect_pixel(t, retina_pixels[40 * 256 + 56], {0, 0, 255, 255})
	expect_pixel(t, retina_pixels[18 * 256 + 18], {})
}

@(private)
test_texture :: proc(device: ^mtl.Device, width, height: int) -> ^mtl.Texture {
	descriptor := mtl.TextureDescriptor.texture2DDescriptorWithPixelFormat(.BGRA8Unorm, ns.UInteger(width), ns.UInteger(height), false)
	descriptor->setUsage({.RenderTarget})
	descriptor->setStorageMode(.Shared)
	texture := device->newTextureWithDescriptor(descriptor)
	assert(texture != nil, "Could not create the offscreen test texture")
	return texture
}

@(private)
test_render :: proc(t: ^testing.T, renderer: ^Metal_Renderer, texture: ^mtl.Texture, rectangles: []primitives.Rectangle, size: [2]f32, pixels: rawptr) {
	pass := mtl.RenderPassDescriptor.renderPassDescriptor()
	attachment := pass->colorAttachments()->object(0)
	attachment->setTexture(texture)
	attachment->setLoadAction(.Clear)
	attachment->setStoreAction(.Store)
	attachment->setClearColor({0, 0, 0, 0})
	command := renderer.queue->commandBuffer()
	encoder := command->renderCommandEncoderWithDescriptor(pass)
	encode_rectangles(renderer, encoder, rectangles, size)
	encoder->endEncoding()
	command->commit()
	command->waitUntilCompleted()
	if command->status() == .Error {
		metal_fail("GPU rendering test failed", command->error())
	}
	testing.expect_value(t, command->status(), mtl.CommandBufferStatus.Completed)
	width, height := texture->width(), texture->height()
	texture->getBytes(pixels, width * 4, {size = {ns.Integer(width), ns.Integer(height), 1}}, 0)
}

@(private)
expect_pixel :: proc(t: ^testing.T, actual, expected: [4]u8, loc := #caller_location) {
	for channel in 0..<4 {
		testing.expect(t, abs(int(actual[channel]) - int(expected[channel])) <= 2,
			"Unexpected GPU pixel value (BGRA)", loc = loc)
	}
}
