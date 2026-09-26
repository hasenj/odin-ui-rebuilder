package platform

import "core:fmt"
import egl "vendor:egl"

// These EGL 1.5 declarations are missing from Odin's vendor:egl bindings.
@(private)
EGL_OPENGL_ES_API :: 0x30A0

foreign import egl_errors "system:EGL"
@(private, default_calling_convention="c")
foreign egl_errors {
	eglGetError :: proc() -> i32 ---
}

@(private)
egl_require :: proc(ok: bool, message: string) {
	if !ok {
		fmt.eprintf("%s (EGL error 0x%04x)\n", message, eglGetError())
		panic(message)
	}
}

// Share the API, configuration and context requirements with the pixel tests.
@(private)
gles_config :: proc(display: egl.Display, surface_type: i32) -> egl.Config {
	egl_require(bool(egl.BindAPI(EGL_OPENGL_ES_API)), "EGL OpenGL ES API is unavailable")
	attributes := [?]i32{
		egl.SURFACE_TYPE, surface_type, egl.RENDERABLE_TYPE, egl.OPENGL_ES3_BIT,
		egl.RED_SIZE, 8, egl.GREEN_SIZE, 8, egl.BLUE_SIZE, 8, egl.ALPHA_SIZE, 8, egl.NONE,
	}
	config: egl.Config
	count: i32
	egl_require(bool(egl.ChooseConfig(display, raw_data(attributes[:]), &config, 1, &count)), "EGL configuration selection failed")
	linux_require(count > 0, "No suitable OpenGL ES 3.0 EGL configuration")
	return config
}

@(private)
gles_context :: proc(display: egl.Display, config: egl.Config) -> egl.Context {
	attributes := [?]i32{egl.CONTEXT_MAJOR_VERSION, 3, egl.CONTEXT_MINOR_VERSION, 0, egl.NONE}
	ctx := egl.CreateContext(display, config, nil, raw_data(attributes[:]))
	egl_require(ctx != nil, "Could not create an OpenGL ES 3.0 context")
	return ctx
}
