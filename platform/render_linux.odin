package platform

import "core:fmt"
import gl "vendor:OpenGL"
import egl "vendor:egl"
import "../core/primitives"

@(private)
GL_Renderer :: struct {
	display: egl.Display,
	surface: egl.Surface,
	program, vao, buffer, white_texture: u32,
	viewport_location: i32,
	pixel_size: [2]i32,
	max_texture_size: i32,
	logical_scale: f32,
	transparent: bool,
	images: [dynamic]Image_Slot,
	free_image: u32,
}

@(private)
GPU_Surface :: struct {
	position, size: [2]f32,
	color: [4]f32,
	radius: f32,
	uv: [4]f32,
}

@(private)
gl_shader :: proc(kind: u32, source: string) -> u32 {
	shader := gl.CreateShader(kind)
	text := cstring(raw_data(source))
	length := i32(len(source))
	gl.ShaderSource(shader, 1, &text, &length)
	gl.CompileShader(shader)
	ok: i32
	gl.GetShaderiv(shader, gl.COMPILE_STATUS, &ok)
	if ok == 0 {
		log: [4096]u8
		gl.GetShaderInfoLog(shader, i32(len(log)), &length, raw_data(log[:]))
		fmt.eprintln(string(log[:length]))
		panic("Could not compile OpenGL surface shader")
	}
	return shader
}

@(private)
gl_init :: proc(renderer: ^GL_Renderer) {
	// Odin's GL bindings share these entry points with GLES. Load through 3.3
	// to include VertexAttribDivisor (desktop 3.3, but core in GLES 3.0).
	// Only GLES 3.0 entry points are used by this renderer.
	gl.load_up_to(3, 3, egl.gl_set_proc_address)
	gl.GetIntegerv(gl.MAX_TEXTURE_SIZE, &renderer.max_texture_size)
	vertex := gl_shader(gl.VERTEX_SHADER, #load("surfaces.vert"))
	fragment := gl_shader(gl.FRAGMENT_SHADER, #load("surfaces.frag"))
	defer gl.DeleteShader(vertex)
	defer gl.DeleteShader(fragment)
	renderer.program = gl.CreateProgram()
	gl.AttachShader(renderer.program, vertex)
	gl.AttachShader(renderer.program, fragment)
	gl.LinkProgram(renderer.program)
	ok: i32
	gl.GetProgramiv(renderer.program, gl.LINK_STATUS, &ok)
	if ok == 0 {
		log: [4096]u8
		length: i32
		gl.GetProgramInfoLog(renderer.program, i32(len(log)), &length, raw_data(log[:]))
		fmt.eprintln(string(log[:length]))
		panic("Could not link OpenGL surface shaders")
	}
	gl.UseProgram(renderer.program)
	renderer.viewport_location = gl.GetUniformLocation(renderer.program, "viewport")
	gl.Uniform1i(gl.GetUniformLocation(renderer.program, "image"), 0)
	gl.GenVertexArrays(1, &renderer.vao)
	gl.GenBuffers(1, &renderer.buffer)
	gl.BindVertexArray(renderer.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, renderer.buffer)
	counts := [?]i32{2, 2, 4, 1, 4}
	offsets := [?]uintptr{offset_of(GPU_Surface, position), offset_of(GPU_Surface, size), offset_of(GPU_Surface, color), offset_of(GPU_Surface, radius), offset_of(GPU_Surface, uv)}
	for count, i in counts {
		gl.EnableVertexAttribArray(u32(i))
		gl.VertexAttribPointer(u32(i), count, gl.FLOAT, false, size_of(GPU_Surface), offsets[i])
		gl.VertexAttribDivisor(u32(i), 1)
	}
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
	renderer.images = make([dynamic]Image_Slot)
	white := [4]u8{255, 255, 255, 255}
	renderer.white_texture = upload_texture(white[:], {1, 1})
	linux_require(renderer.white_texture != 0, "Could not create the solid-color texture")
}

@(private)
gl_destroy :: proc(renderer: ^GL_Renderer) {
	for slot in renderer.images {
		if slot.texture != 0 {
			texture := slot.texture
			gl.DeleteTextures(1, &texture)
		}
	}
	delete(renderer.images)
	gl.DeleteTextures(1, &renderer.white_texture)
	gl.DeleteBuffers(1, &renderer.buffer)
	gl.DeleteVertexArrays(1, &renderer.vao)
	gl.DeleteProgram(renderer.program)
}

@(private)
render_impl :: proc(handle: Renderer, surfaces: []primitives.Surface, size: [2]f32, timing: ^Render_Timing) {
	renderer := cast(^GL_Renderer)handle
	gl_render_frame(renderer, surfaces, size)
	// EGL combines presentation work and pacing in one call; account for its
	// entire duration as waits rather than pretending to isolate sleep time.
	wait_start := render_wait_begin(timing)
	swapped := bool(egl.SwapBuffers(renderer.display, renderer.surface))
	render_wait_end(timing, wait_start)
	linux_require(swapped, "EGL buffer swap failed")
}

// Shared by window rendering and pixel readback tests, including the clear.
@(private)
gl_render_frame :: proc(renderer: ^GL_Renderer, surfaces: []primitives.Surface, size: [2]f32) {
	gl.Viewport(0, 0, renderer.pixel_size.x, renderer.pixel_size.y)
	if renderer.transparent {
		gl.ClearColor(0, 0, 0, 0)
	} else {
		gl.ClearColor(0.035, 0.045, 0.065, 1)
	}
	gl.Clear(gl.COLOR_BUFFER_BIT)
	encode_surfaces(renderer, surfaces, size)
}

@(private)
encode_surfaces :: proc(renderer: ^GL_Renderer, surfaces: []primitives.Surface, size: [2]f32) {
	if size.x <= 0 || size.y <= 0 {
		return
	}
	gl.UseProgram(renderer.program)
	gl.Uniform2f(renderer.viewport_location, size.x, size.y)
	gl.BindVertexArray(renderer.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, renderer.buffer)
	gl.ActiveTexture(gl.TEXTURE0)
	batch: [64]GPU_Surface
	count := 0
	batch_texture: u32
	for surface in surfaces {
		if surface.size.x <= 0 || surface.size.y <= 0 {
			continue
		}
		texture := renderer.white_texture
		if surface.image != (primitives.Image{}) {
			slot := lookup_image(renderer, surface.image)
			if slot == nil {
				continue
			}
			texture = slot.texture
		}
		if count > 0 && texture != batch_texture {
			gl_batch(batch[:count], batch_texture)
			count = 0
		}
		batch_texture = texture
		batch[count] = {surface.position, surface.size, surface.background, clamp(surface.corner_radius, 0, min(surface.size.x, surface.size.y) * 0.5),
			surface.image_region if surface.image_region != ([4]f32{}) else [4]f32{0, 0, 1, 1}}
		for &component in batch[count].color {
			component = clamp(component, 0, 1)
		}
		count += 1
		if count == len(batch) {
			gl_batch(batch[:count], batch_texture)
			count = 0
		}
	}
	if count > 0 {
		gl_batch(batch[:count], batch_texture)
	}
}

@(private)
gl_batch :: proc(batch: []GPU_Surface, texture: u32) {
	gl.BindTexture(gl.TEXTURE_2D, texture)
	// Orphaning gives the driver fresh backing storage while prior draws finish.
	gl.BufferData(gl.ARRAY_BUFFER, len(batch) * size_of(GPU_Surface), raw_data(batch), gl.STREAM_DRAW)
	gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, i32(len(batch)))
}

@(private)
pixel_scale_impl :: proc(handle: Renderer) -> f32 {
	return max((cast(^GL_Renderer)handle).logical_scale, 1)
}
