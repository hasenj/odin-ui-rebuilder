#+build darwin
package platform

import "core:testing"
import ns "core:sys/darwin/Foundation"
import mtl "vendor:darwin/Metal"
import "../core/primitives"
import "../core/images"

// Runs the actual shader and blend pipeline, then reads GPU output back.
// Run on a Mac with a Metal GPU: odin test platform -out:bin/platform-tests
@(test)
metal_surface_rendering :: proc(t: ^testing.T) {
	ns.scoped_autoreleasepool()
	renderer: Metal_Renderer
	metal_init(&renderer)
	defer metal_destroy(&renderer)
	texture := test_texture(renderer.device, 128, 96)
	defer texture->release()
	pixels: [128 * 96][4]u8
	scene := [?]primitives.Surface{
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

	// Hard rectangular clips use logical coordinates, independently of rounded
	// geometry. An enabled empty clip must not become an unbounded clip.
	clipped := [?]primitives.Surface{
		{size = {100, 90}, background = {1, 0, 0, 1}, clip = {true, {10, 20}, {30, 40}}},
		{size = {100, 90}, background = {0, 1, 0, 1}, clip = {true, {50, 50}, {50, 60}}},
	}
	test_render(t, &renderer, texture, clipped[:], {128, 96}, raw_data(pixels[:]))
	expect_pixel(t, pixels[20 * 128 + 10], {0, 0, 255, 255})
	expect_pixel(t, pixels[39 * 128 + 29], {0, 0, 255, 255})
	expect_pixel(t, pixels[19 * 128 + 10], {})
	expect_pixel(t, pixels[20 * 128 + 30], {})
	expect_pixel(t, pixels[40 * 128 + 29], {})
	expect_pixel(t, pixels[50 * 128 + 50], {})

	// The same render target must not retain anything from the previous list.
	test_render(t, &renderer, texture, nil, {128, 96}, raw_data(pixels[:]))
	for pixel in pixels {
		if !testing.expect_value(t, pixel, [4]u8{}) {
			break
		}
	}

	// More than two inline batches, including a skipped degenerate surface.
	batch_scene: [131]primitives.Surface
	for &surface in batch_scene {
		surface = {position = {8, 8}, size = {40, 40}, background = {1, 0, 0, 1}}
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
	test_render(t, &renderer, retina, clipped[:], {128, 96}, raw_data(retina_pixels))
	expect_pixel(t, retina_pixels[40 * 256 + 20], {0, 0, 255, 255})
	expect_pixel(t, retina_pixels[79 * 256 + 59], {0, 0, 255, 255})
	expect_pixel(t, retina_pixels[40 * 256 + 19], {})
	expect_pixel(t, retina_pixels[40 * 256 + 60], {})


	// Decode a known PNG and exercise upload, sampling, mixed draw order, tint,
	// clipping, handle reuse, and destruction through the actual GPU pipeline.
	decoded, decode_error := images.load_bytes(#load("../core/images/testdata/rgba.png", []u8))
	if !testing.expect(t, decode_error == nil) {
		return
	}
	image, image_error := create_image(Renderer(&renderer), decoded.pixels.buf[:], {decoded.width, decoded.height})
	images.destroy(decoded) // Upload must not retain CPU pixels.
	if !testing.expect_value(t, image_error, Image_Error.None) {
		return
	}
	image_scene := [?]primitives.Surface{
		{size = {128, 96}, background = {1, 1, 1, 1}},
		{position = {8, 8}, size = {64, 64}, background = {1, 1, 1, 1}, image = image},
		{position = {80, 8}, size = {40, 40}, background = {0.5, 1, 1, 0.5}, corner_radius = 12, image = image},
		{position = {24, 24}, size = {8, 8}, background = {0, 0, 0, 1}},
	}
	test_render(t, &renderer, texture, image_scene[:], {128, 96}, raw_data(pixels[:]))
	expect_pixel(t, pixels[16 * 128 + 16], {0, 0, 255, 255}) // Top-left red.
	expect_pixel(t, pixels[16 * 128 + 64], {0, 255, 0, 255}) // Top-right green.
	expect_pixel(t, pixels[64 * 128 + 16], {255, 127, 127, 255}) // Half-blue over white.
	expect_pixel(t, pixels[64 * 128 + 64], {255, 255, 255, 255}) // Transparent texel.
	expect_pixel(t, pixels[26 * 128 + 26], {0, 0, 0, 255}) // Solid overlays image.
	expect_pixel(t, pixels[9 * 128 + 81], {255, 255, 255, 255}) // Rounded image corner.
	expect_pixel(t, pixels[17 * 128 + 89], {128, 128, 191, 255}) // Tint and opacity.
	testing.expect_value(t, len(renderer.images), 1) // One resource, multiple draws.
	original_size, size_ok := image_size(Renderer(&renderer), image)
	testing.expect(t, size_ok)
	testing.expect_value(t, original_size, [2]int{2, 2})
	invalid_handles := [?]primitives.Image{
		{},
		{index = max(u32), generation = 1},
		{index = image.index, generation = image.generation + 1},
	}
	for invalid in invalid_handles {
		_, ok := image_size(Renderer(&renderer), invalid)
		testing.expect(t, !ok)
		destroy_image(Renderer(&renderer), invalid)
	}

	destroy_image(Renderer(&renderer), image)
	destroy_image(Renderer(&renderer), image) // Repeated destruction is harmless.
	_, released_ok := image_size(Renderer(&renderer), image)
	testing.expect(t, !released_ok)
	test_render(t, &renderer, texture, image_scene[1:2], {128, 96}, raw_data(pixels[:]))
	expect_pixel(t, pixels[16 * 128 + 16], {}) // Stale handles are skipped.
	white := [4]u8{255, 255, 255, 255}
	replacement, replacement_error := create_image(Renderer(&renderer), white[:], {1, 1})
	testing.expect_value(t, replacement_error, Image_Error.None)
	testing.expect_value(t, replacement.index, image.index)
	testing.expect(t, replacement.generation != image.generation)
	testing.expect_value(t, len(renderer.images), 1) // Reuses the original slot.
	// The old handle must neither draw nor destroy its replacement.
	test_render(t, &renderer, texture, image_scene[1:2], {128, 96}, raw_data(pixels[:]))
	expect_pixel(t, pixels[16 * 128 + 16], {})
	destroy_image(Renderer(&renderer), image)
	replacement_size, replacement_ok := image_size(Renderer(&renderer), replacement)
	testing.expect(t, replacement_ok)
	testing.expect_value(t, replacement_size, [2]int{1, 1})
	_, stale_ok := image_size(Renderer(&renderer), image)
	testing.expect(t, !stale_ok)
	image_scene[1].image = replacement
	test_render(t, &renderer, texture, image_scene[1:2], {128, 96}, raw_data(pixels[:]))
	expect_pixel(t, pixels[16 * 128 + 16], {255, 255, 255, 255})

	// Exercise a free list with multiple slots, including a repeated release.
	second, second_error := create_image(Renderer(&renderer), white[:], {1, 1})
	testing.expect_value(t, second_error, Image_Error.None)
	destroy_image(Renderer(&renderer), replacement)
	destroy_image(Renderer(&renderer), second)
	destroy_image(Renderer(&renderer), second)
	reused_second, reused_second_error := create_image(Renderer(&renderer), white[:], {1, 1})
	reused_first, reused_first_error := create_image(Renderer(&renderer), white[:], {1, 1})
	testing.expect_value(t, reused_second_error, Image_Error.None)
	testing.expect_value(t, reused_first_error, Image_Error.None)
	testing.expect_value(t, reused_second.index, second.index)
	testing.expect_value(t, reused_first.index, replacement.index)
	testing.expect_value(t, len(renderer.images), 2)

	// Exhausted generations retire the slot rather than reviving old handles.
	renderer.images[reused_first.index - 1].generation = max(u32)
	exhausted := primitives.Image{index = reused_first.index, generation = max(u32)}
	destroy_image(Renderer(&renderer), exhausted)
	after_exhaustion, exhaustion_error := create_image(Renderer(&renderer), white[:], {1, 1})
	testing.expect_value(t, exhaustion_error, Image_Error.None)
	testing.expect(t, after_exhaustion.index != exhausted.index)
	_, exhausted_ok := image_size(Renderer(&renderer), exhausted)
	testing.expect(t, !exhausted_ok)
	destroy_image(Renderer(&renderer), reused_second)
	destroy_image(Renderer(&renderer), after_exhaustion)

	// Atlas UVs select distinct regions of one texture. Updating the right half
	// must be ordered before drawing without disturbing the left half.
	atlas_pixels: [4 * 4 * 4]u8
	for i in 0..<16 { atlas_pixels[i * 4] = 255; atlas_pixels[i * 4 + 3] = 255 }
	atlas, atlas_error := create_image(Renderer(&renderer), atlas_pixels[:], {4, 4})
	testing.expect_value(t, atlas_error, Image_Error.None)
	defer destroy_image(Renderer(&renderer), atlas)
	patch: [2 * 4 * 4]u8
	for &channel in patch { channel = 128 }
	testing.expect_value(t, update_image(Renderer(&renderer), atlas, patch[:], {2, 0}, {2, 4}), Image_Error.None)
	testing.expect_value(t, update_image(Renderer(&renderer), atlas, patch[:], {3, 0}, {2, 4}), Image_Error.Invalid_Pixels)
	testing.expect_value(t, update_image(Renderer(&renderer), {}, patch[:], {0, 0}, {2, 4}), Image_Error.Invalid_Image)
	atlas_scene := [?]primitives.Surface{
		{position = {8, 8}, size = {40, 40}, background = {1, 1, 1, 1}, image = atlas, image_region = {0, 0, 0.5, 1}},
		{position = {60, 8}, size = {40, 40}, background = {0, 0, 1, 1}, image = atlas, image_region = {0.5, 0, 1, 1}},
	}
	test_render(t, &renderer, texture, atlas_scene[:], {128, 96}, raw_data(pixels[:]))
	expect_pixel(t, pixels[28 * 128 + 28], {0, 0, 255, 255})
	expect_pixel(t, pixels[28 * 128 + 80], {128, 0, 0, 128})
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
test_render :: proc(t: ^testing.T, renderer: ^Metal_Renderer, texture: ^mtl.Texture, surfaces: []primitives.Surface, size: [2]f32, pixels: rawptr) {
	pass := mtl.RenderPassDescriptor.renderPassDescriptor()
	attachment := pass->colorAttachments()->object(0)
	attachment->setTexture(texture)
	attachment->setLoadAction(.Clear)
	attachment->setStoreAction(.Store)
	attachment->setClearColor({0, 0, 0, 0})
	command := renderer.queue->commandBuffer()
	encoder := command->renderCommandEncoderWithDescriptor(pass)
	encode_surfaces(renderer, encoder, surfaces, size)
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
