package platform

import "base:runtime"
import "core:c"

@(private)
PNG_Output :: struct {bytes: [dynamic]u8, odin_context: runtime.Context}

@(private)
png_write :: proc "c" (user_data: rawptr, data: rawptr, size: c.int) {
	output := cast(^PNG_Output)user_data
	context = output.odin_context
	append(&output.bytes, ..(cast([^]u8)data)[:int(size)])
}
