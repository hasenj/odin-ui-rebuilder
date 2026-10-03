package ui

import "input"
import "../platform"

Text_Operation :: input.Text_Operation
Text_Command :: input.Text_Command
Text_Range :: input.Text_Range
clipboard_read :: platform.clipboard_read // Owned UTF-8 string; caller deletes it.
clipboard_write :: platform.clipboard_write

// Request native input for the current directly focused identity. Publish only
// once per frame, after applying input. Text must live until this update ends.
// Call every frame while active; omission disables the client. Ranges use bytes.
request_text_input :: proc(value: string, selection: Text_Range, caret: Rect, marked: Text_Range = input.NO_TEXT_RANGE) {
	id := current_identity()
	if direct_focus() != id { return }
	frame := current_frame()
	frame.text_client = {target = text_target(id), value = value, selection = selection,
		marked = marked, has_marked = marked.start >= 0, caret_position = caret.position, caret_size = caret.size}
}
text_target :: proc(id: Identity) -> u64 { return u64(id.generation) << 32 | u64(id.index) }
