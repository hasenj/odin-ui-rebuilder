#+build linux
package platform

import "core:testing"
import egl "vendor:egl"
import gl "vendor:OpenGL"
import "../core/primitives"
import "../core/images"

// Uses Mesa's surfaceless EGL platform, so this test needs no visible desktop.
// It exercises the actual GLSL shaders and image resource lifecycle.
// -define:WAYLAND_RENDER_TEST=true uses the live compositor's EGL driver instead.
@(test)
gl_surface_rendering :: proc(t: ^testing.T) {
	egl_state := test_egl_context()
	defer destroy_test_egl_context(egl_state)
	renderer := GL_Renderer{transparent = true}
	gl_init(&renderer)
	defer gl_destroy(&renderer)
	texture := test_texture( 128, 96)
	defer destroy_test_texture(texture)
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


	// Analytic/fixed-sample shadows: interior, soft exterior, finite extent and
	// hollow outlines. Pixel readback exercises actual shader execution.
	shadows := [?]primitives.Surface{
		{position = {24, 24}, size = {40, 40}, background = {1, 1, 1, 1}, shadow_sigma = 4, corner_radius = 6},
		{position = {80, 24}, size = {24, 24}, background = {1, 0, 0, 1}, border_width = 2, corner_radius = 4},
	}
	test_render(t, &renderer, texture, shadows[:], {128, 96}, raw_data(pixels[:]))
	testing.expect(t, pixels[44*128+44][3] >= 250, "Shadow center should be opaque")
	testing.expect(t, pixels[44*128+23][3] > 100 && pixels[44*128+23][3] < 140, "Shadow boundary should approach half coverage")
	testing.expect(t, pixels[44*128+19][3] > 15 && pixels[44*128+19][3] < 55, "Blur must extend beyond layout bounds")
	testing.expect_value(t, pixels[44*128+10][3], u8(0))
	testing.expect_value(t, pixels[35*128+92][3], u8(0)) // Hollow center.
	testing.expect(t, pixels[35*128+80][3] > 240, "Outline edge should be visible")
	shadows[0].clip = {true, {24, 24}, {64, 64}}
	test_render(t, &renderer, texture, shadows[:], {128, 96}, raw_data(pixels[:]))
	testing.expect_value(t, pixels[44*128+23][3], u8(0)) // Active clipping applies to blur too.

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

	// Opaque windows keep the old dark background and composite alpha over it.
	renderer.transparent = false
	test_render(t, &renderer, texture, scene[:], {128, 96}, raw_data(pixels[:]))
	expect_pixel(t, pixels[9 * 128 + 9], {17, 11, 9, 255})
	expect_pixel(t, pixels[30 * 128 + 56], {136, 6, 4, 255})
	test_render(t, &renderer, texture, nil, {128, 96}, raw_data(pixels[:]))
	expect_pixel(t, pixels[20 * 128 + 28], {17, 11, 9, 255})
	renderer.transparent = true

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
	retina := test_texture( 256, 192)
	defer destroy_test_texture(retina)
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
Test_EGL_Context :: struct {display: egl.Display, ctx: egl.Context, wayland: rawptr}

@(private)
test_egl_context :: proc() -> Test_EGL_Context {
	display: egl.Display
	wayland: rawptr
	surface_type: i32 = 1 // EGL_PBUFFER_BIT
	when #config(WAYLAND_RENDER_TEST, false) {
		wayland = wl_display_connect(nil)
		linux_require(wayland != nil, "Tests require a live Wayland session")
		display = egl.GetPlatformDisplay(.WAYLAND_KHR, wayland, nil)
		surface_type = egl.WINDOW_BIT
	} else {
		display = egl.GetPlatformDisplay(.SURFACELESS_MESA, nil, nil)
	}
	linux_require(bool(egl.Initialize(display, nil, nil)), "Could not initialize test EGL display")
	config := gles_config(display, surface_type)
	ctx := gles_context(display, config)
	linux_require(bool(egl.MakeCurrent(display, nil, nil, ctx)), "Could not make test GLES context current")
	return {display, ctx, wayland}
}

@(private)
destroy_test_egl_context :: proc(state: Test_EGL_Context) {
	egl.MakeCurrent(state.display, nil, nil, nil)
	egl.DestroyContext(state.display, state.ctx)
	egl.Terminate(state.display)
	if state.wayland != nil {
		wl_display_disconnect(state.wayland)
	}
}

@(private)
Test_Texture :: struct {texture, framebuffer: u32, width, height: i32}

@(private)
test_texture :: proc(width, height: i32) -> Test_Texture {
	target := Test_Texture{width = width, height = height}
	gl.GenTextures(1, &target.texture)
	gl.BindTexture(gl.TEXTURE_2D, target.texture)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
	gl.GenFramebuffers(1, &target.framebuffer)
	gl.BindFramebuffer(gl.FRAMEBUFFER, target.framebuffer)
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, target.texture, 0)
	assert(gl.CheckFramebufferStatus(gl.FRAMEBUFFER) == gl.FRAMEBUFFER_COMPLETE)
	return target
}

@(private)
destroy_test_texture :: proc(target: Test_Texture) {
	texture, framebuffer := target.texture, target.framebuffer
	gl.DeleteFramebuffers(1, &framebuffer)
	gl.DeleteTextures(1, &texture)
}

@(private)
test_render :: proc(t: ^testing.T, renderer: ^GL_Renderer, target: Test_Texture, surfaces: []primitives.Surface, size: [2]f32, pixels: rawptr) {
	gl.BindFramebuffer(gl.FRAMEBUFFER, target.framebuffer)
	renderer.pixel_size = {target.width, target.height}
	gl_render_frame(renderer, surfaces, size)
	gl.ReadPixels(0, 0, target.width, target.height, gl.RGBA, gl.UNSIGNED_BYTE, pixels)
	testing.expect_value(t, gl.GetError(), u32(gl.NO_ERROR))
	// ReadPixels returns bottom-to-top rows; expectations use the UI's top-left origin.
	data := cast([^][4]u8)pixels
	// GLES guarantees RGBA readback. Keep the BGRA expectations shared with Metal.
	for i in 0..<target.width * target.height {
		data[i][0], data[i][2] = data[i][2], data[i][0]
	}
	for y in 0..<target.height / 2 {
		for x in 0..<target.width {
			a := y * target.width + x
			b := (target.height - 1 - y) * target.width + x
			data[a], data[b] = data[b], data[a]
		}
	}
}

@(private)
expect_pixel :: proc(t: ^testing.T, actual, expected: [4]u8, loc := #caller_location) {
	for channel in 0..<4 {
		testing.expect(t, abs(int(actual[channel]) - int(expected[channel])) <= 2,
			"Unexpected GPU pixel value (BGRA)", loc = loc)
	}
}
