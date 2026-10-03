package platform

import "core:c"
import "core:math"
import "core:mem"
import "core:os"
import egl "vendor:egl"
import gl "vendor:OpenGL"
import stb "vendor:stb/image"
import "../core/input"
import "../core/primitives"

foreign import egl_capture "system:EGL"
@(private)
foreign egl_capture {
	eglGetCurrentDisplay :: proc "c" () -> egl.Display ---
	eglGetCurrentContext :: proc "c" () -> egl.Context ---
	eglGetCurrentSurface :: proc "c" (which: i32) -> egl.Surface ---
}

@(private)
capture_frames_impl :: proc(frames: []Capture_Frame, frame: Frame_Proc, user_data: rawptr, input_state: ^input.State) -> Capture_Result {
	temporary: mem.Dynamic_Arena
	mem.dynamic_arena_init(&temporary)
	defer mem.dynamic_arena_destroy(&temporary)
	context.temp_allocator = mem.dynamic_arena_allocator(&temporary)
	old_display, old_context := eglGetCurrentDisplay(), eglGetCurrentContext()
	old_draw, old_read := eglGetCurrentSurface(0x3059), eglGetCurrentSurface(0x305A)
	defer { if old_display != nil { egl.MakeCurrent(old_display, old_draw, old_read, old_context) } }
	display := egl.GetPlatformDisplay(.SURFACELESS_MESA, nil, nil)
	if !bool(egl.Initialize(display, nil, nil)) { return {.Render_Failed, -1} }
	defer egl.Terminate(display)
	if !bool(egl.BindAPI(EGL_OPENGL_ES_API)) { return {.Render_Failed, -1} }
	attributes := [?]i32{egl.SURFACE_TYPE, 1, egl.RENDERABLE_TYPE, egl.OPENGL_ES3_BIT, egl.NONE}
	config: egl.Config
	count: i32
	if !bool(egl.ChooseConfig(display, raw_data(attributes[:]), &config, 1, &count)) || count == 0 { return {.Render_Failed, -1} }
	context_attributes := [?]i32{egl.CONTEXT_MAJOR_VERSION, 3, egl.NONE}
	ctx := egl.CreateContext(display, config, nil, raw_data(context_attributes[:]))
	if ctx == nil { return {.Render_Failed, -1} }
	defer egl.DestroyContext(display, ctx)
	if !bool(egl.MakeCurrent(display, nil, nil, ctx)) { return {.Render_Failed, -1} }
	defer egl.MakeCurrent(display, nil, nil, nil)
	renderer: GL_Renderer
	gl_init(&renderer)
	defer gl_destroy(&renderer)
	for item, i in frames {
		if err := capture_one_frame(&renderer, item, frame, user_data, input_state); err != .None { return {err, i} }
	}
	return {frame_index = -1}
}

@(private)
capture_one_frame :: proc(renderer: ^GL_Renderer, item: Capture_Frame, frame: Frame_Proc, user_data: rawptr, input_state: ^input.State) -> Capture_Error {
	defer free_all(context.temp_allocator)
	renderer.logical_scale = item.scale
	if input_state != nil { input_state^ = item.input }
	surfaces: []primitives.Surface
	if frame != nil { surfaces = frame(Renderer(renderer), item.time, item.size, user_data) }
	if item.path == "" { return .None }
	width := i32(math.ceil(f64(item.size.x) * f64(item.scale)))
	height := i32(math.ceil(f64(item.size.y) * f64(item.scale)))
	if width > renderer.max_texture_size || height > renderer.max_texture_size { return .Render_Failed }
	texture, framebuffer: u32
	gl.GenTextures(1, &texture)
	defer gl.DeleteTextures(1, &texture)
	gl.BindTexture(gl.TEXTURE_2D, texture)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
	gl.GenFramebuffers(1, &framebuffer)
	defer gl.DeleteFramebuffers(1, &framebuffer)
	gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer)
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0)
	if gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE { return .Render_Failed }
	gl.Viewport(0, 0, width, height)
	color := item.clear_color
	gl.ClearColor(color.r * color.a, color.g * color.a, color.b * color.a, color.a)
	gl.Clear(gl.COLOR_BUFFER_BIT)
	encode_surfaces(renderer, surfaces, item.size)
	pixels := make([][4]u8, int(width) * int(height))
	defer delete(pixels)
	gl.ReadPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))
	if gl.GetError() != gl.NO_ERROR { return .Render_Failed }
	// GLES returns bottom-up premultiplied RGBA; PNG needs top-down straight RGBA.
	for y in 0..<int(height) / 2 {
		for x in 0..<int(width) {
			a, b := y * int(width) + x, (int(height) - 1 - y) * int(width) + x
			pixels[a], pixels[b] = pixels[b], pixels[a]
		}
	}
	for &pixel in pixels {
		alpha := u32(pixel[3])
		if alpha == 0 { pixel = {}; continue }
		for j in 0..<3 { pixel[j] = u8(min(255, (u32(pixel[j]) * 255 + alpha / 2) / alpha)) }
	}
	output := PNG_Output{odin_context = context}
	defer delete(output.bytes)
	if stb.write_png_to_func(png_write, &output, c.int(width), c.int(height), 4, raw_data(pixels), c.int(width * 4)) == 0 { return .Write_Failed }
	if os.write_entire_file(item.path, output.bytes[:]) != nil { return .Write_Failed }
	return .None
}
