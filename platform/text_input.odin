package platform

import "../core/input"

// Availability of native services, not whether an IME daemon is installed or
// whether clipboard access currently has focus/an input serial. Capture has none.
Text_Input_Capabilities :: struct {typing, composition, clipboard: bool}

text_input_capabilities :: proc(renderer: Renderer) -> Text_Input_Capabilities {
	if renderer == nil { return {} }
	when ODIN_OS == .Darwin {
		if (cast(^Metal_Renderer)renderer).view != nil { return {true, true, true} }
	} else when ODIN_OS == .Linux {
		w := (cast(^GL_Renderer)renderer).window
		if w != nil { return {w.xkb_state != nil || w.text_input.proxy != nil, w.text_input.proxy != nil, w.clipboard.device != nil} }
	}
	return {}
}

// Shared native text services.
// Core still accepts synthetic Text_Input data on every backend.
text_input_update :: proc(renderer: Renderer, client: input.Text_Client) -> bool {
	when ODIN_OS == .Darwin {
		if renderer == nil || (cast(^Metal_Renderer)renderer).view == nil { return false }
		macos_text_sync(cast(^Metal_Renderer)renderer, client)
		return true
	} else when ODIN_OS == .Linux {
		if renderer == nil { return false }; w := (cast(^GL_Renderer)renderer).window
		if w == nil { return false }; wayland_text_sync(w, client); return text_input_capabilities(renderer).typing
	} else { return false }
}
clipboard_read :: proc() -> (string, bool) {
	when ODIN_OS == .Darwin { return macos_clipboard_read() } else when ODIN_OS == .Linux { return wayland_clipboard_read() } else { return "", false }
}
clipboard_write :: proc(value: string) -> bool {
	when ODIN_OS == .Darwin { return macos_clipboard_write(value) } else when ODIN_OS == .Linux { return wayland_clipboard_write(value) } else { return false }
}
