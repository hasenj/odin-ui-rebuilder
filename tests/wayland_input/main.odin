#+build linux
package wayland_input_check

import "../../platform"
import "../../core/input"
import edit "../../core/edit"
import "../../core/primitives"
import "core:fmt"

state, panel_state: input.State
buffer, panel_buffer: edit.Buffer
window: platform.Window
copied, pasted, submitted: bool

main :: proc() {
	edit.init(&buffer); defer edit.destroy(&buffer)
	edit.init(&panel_buffer); defer edit.destroy(&panel_buffer)
	platform.init(); defer platform.shutdown()
	window = platform.create_window("Wayland native text check", 360, 180, update, input_state = &state)
	platform.create_panel("Wayland native panel check", 220, 120, panel_update, input_state = &panel_state)
	platform.run()
	assert(edit.value(&panel_buffer) == "p", "Panel keyboard input leaked across surfaces")
	assert(submitted && copied && pasted)
	assert(edit.value(&buffer) == "cab外", edit.value(&buffer))
	fmt.println("Verified native Wayland typing, select-all, clipboard copy/paste, submit, and main/panel input isolation")
}

update :: proc(renderer: platform.Renderer, elapsed: f64, _: [2]f32, _: rawptr) -> []primitives.Surface {
	assert(elapsed < 30, "Native input test timed out")
	for op in state.text.operations {
		if op.kind == .Command {
			#partial switch op.command {
			case .Copy:
				range := edit.selection(&buffer)
				copied = platform.clipboard_write(edit.value(&buffer)[range.start:range.end]); continue
			case .Paste:
				value, ok := platform.clipboard_read(); pasted = ok
				if ok { edit.apply(&buffer, {kind = .Commit, text = value}); delete(value) }; continue
			case .Submit: submitted = true; platform.request_close(window); continue
			}
		}
		edit.apply(&buffer, op)
	}
	platform.text_input_update(renderer, {target = 1, value = edit.value(&buffer), selection = edit.selection(&buffer), marked = buffer.marked,
		has_marked = buffer.composing, caret_position = {20, 20}, caret_size = {1, 20}})
	return nil
}

panel_update :: proc(renderer: platform.Renderer, _: f64, _: [2]f32, _: rawptr) -> []primitives.Surface {
	for op in panel_state.text.operations { edit.apply(&panel_buffer, op) }
	platform.text_input_update(renderer, {target = 2, value = edit.value(&panel_buffer), selection = edit.selection(&panel_buffer), marked = panel_buffer.marked,
		has_marked = panel_buffer.composing, caret_position = {20, 20}, caret_size = {1, 20}})
	return nil
}
