package platform

import "../core/input"

// Shared API; native Wayland implementation is intentionally left to its host.
// Core still accepts synthetic Text_Input data on every backend.
text_input_update :: proc(renderer: Renderer, client: input.Text_Client) -> bool {
	when ODIN_OS == .Darwin {
		if renderer == nil || (cast(^Metal_Renderer)renderer).view == nil { return false }
		macos_text_sync(cast(^Metal_Renderer)renderer, client)
		return true
	} else { return false }
}
clipboard_read :: proc() -> (string, bool) {
	when ODIN_OS == .Darwin { return macos_clipboard_read() } else { return "", false }
}
clipboard_write :: proc(value: string) -> bool {
	when ODIN_OS == .Darwin { return macos_clipboard_write(value) } else { return false }
}
