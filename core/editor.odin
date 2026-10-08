package ui

import edit "edit"
import "input"
import fonts "text"
import "core:math"

// Low-level editing engine storage. Ordinary fields use edit_text(^string /
// ^[dynamic]u8), which retains this internally under the field identity.
Text_Edit :: struct {
	buffer: edit.Buffer,
	spans: [dynamic]fonts.Caret_Span,
	metrics: Text_Metrics,
	prepared: bool,
	prepared_revision: u64,
	font: Font,
	catalog_generation: u64,
	size, scale, scroll: f32,
	dragging: bool,
	previous: Mouse_Buttons,
	caret_x: f32,
	caret_byte: int,
	caret_time: f64,
}
Text_Edit_Result :: struct {changed, submitted: bool, error: Text_Error, composing, empty: bool}
init_text_edit :: proc(editor: ^Text_Edit, value: string = "") { edit.init(&editor.buffer, value) }
destroy_text_edit :: proc(editor: ^Text_Edit) { edit.destroy(&editor.buffer); delete(editor.spans); editor^ = {} }
text_edit_value :: proc(editor: ^Text_Edit) -> string { return edit.value(&editor.buffer) }

// Draw/operate within the current rect. Input is still available to all code;
// text operations are associated with the identity that owned native input.
edit_text_state :: proc(editor: ^Text_Edit, font: Font_Ref, size: f32 = 20, color: Color = {0.93, 0.95, 0.98, 1}, selection_color: Color = {0.18, 0.39, 0.68, 0.8}, align: Text_Align = .Start, enabled: bool = true, accept_input: bool = true) -> Text_Edit_Result {
	assert(!active_state.layout.active, "Text editing requires resolved geometry")
	frame := current_frame()
	id := current_identity()
	focusable(enabled)
	b := &editor.buffer
	revision := b.revision
	before_cursor, before_anchor := b.cursor, b.anchor
	result: Text_Edit_Result
	handle := resolve_font(font)
	r := current_rect()
	result.error = prepare_editor(editor, handle, size)
	snapshot := frame.input
	pressed := snapshot.mouse_pressed | (snapshot.mouse_buttons & ~editor.previous)
	released := snapshot.mouse_released | (editor.previous & ~snapshot.mouse_buttons)
	editor.previous = snapshot.mouse_buttons
	// Apply text already delivered to this field even if a click in this frame
	// moves focus elsewhere. Never deliver it to the newly focused field.
	for operation in snapshot.text.operations {
		if !enabled || !accept_input { break }
		target := operation.target if operation.target != 0 else snapshot.text.target
		if target != text_target(id) { continue }
		if operation.kind == .Command {
			if operation.command == .Submit { result.submitted = true; continue }
			if operation.command == .Copy || operation.command == .Cut {
				range := edit.selection(b)
				if range.start != range.end && clipboard_write(edit.value(b)[range.start:range.end]) && operation.command == .Cut {
					edit.apply(b, {kind = .Commit})
				}
				continue
			}
			if operation.command == .Paste {
				if value, ok := clipboard_read(); ok { edit.apply(b, {kind = .Commit, text = value}); delete(value) }
				continue
			}
			if operation.command == .Left || operation.command == .Right {
				edit.finish_composition(b)
				if err := prepare_editor(editor, handle, size); err == .None { move_visual(editor, operation.command == .Right, operation.extend) }
				continue
			}
		}
		edit.apply(b, operation)
	}
	if err := prepare_editor(editor, handle, size); err != .None {
		result.error = err
		if enabled { request_text_input(edit.value(b), edit.selection(b), Rect{r.position, {1.5, size}}, b.marked if b.composing else input.NO_TEXT_RANGE) }
		result.composing, result.empty = b.composing, len(b.bytes) == 0
		result.changed = b.revision != revision
		return result
	}
	if !enabled || snapshot.mouse_cancelled || direct_focus() != id { editor.dragging = false }
	// Short lines can align within the field; overflowing lines retain the
	// usual horizontal scrolling. Share this offset with hit testing and IME.
	spare := max(0, r.size.x - editor.metrics.width - 2)
	alignment_x := spare/2 if align == .Center else spare if align == .End else 0
	if enabled && accept_input && hovered() && .Left in pressed && !snapshot.mouse_cancelled {
		edit.finish_composition(b)
		index, x := hit_caret(editor, snapshot.mouse_position.x - r.position.x - alignment_x + editor.scroll)
		b.cursor = index
		if .Shift not_in snapshot.modifiers { b.anchor = index }
		editor.caret_byte, editor.caret_x = index, x
		editor.dragging = .Left in snapshot.mouse_buttons
	}
	if editor.dragging {
		index, x := hit_caret(editor, snapshot.mouse_position.x - r.position.x - alignment_x + editor.scroll)
		b.cursor = index; editor.caret_byte, editor.caret_x = index, x
		if .Left in released || .Left not_in snapshot.mouse_buttons { editor.dragging = false }
	}
	if direct_focus() != id { edit.finish_composition(b) }
	if b.cursor != editor.caret_byte || b.revision != revision { editor.caret_x = caret_position(editor, b.cursor); editor.caret_byte = b.cursor }
	if before_cursor != b.cursor || before_anchor != b.anchor || b.revision != revision || .Left in pressed { editor.caret_time = frame.time }
	if enabled && direct_focus() == id {
		if editor.caret_x < editor.scroll { editor.scroll = editor.caret_x }
		if editor.caret_x > editor.scroll + max(0, r.size.x - 2) { editor.scroll = editor.caret_x - max(0, r.size.x - 2) }
	}
	editor.scroll = clamp(editor.scroll, 0, max(0, editor.metrics.width - r.size.x + 2))
	origin := r.position + [2]f32{alignment_x-editor.scroll, max(0, (r.size.y - editor.metrics.height) / 2)}
	open_clip(r)
	selection := edit.selection(b)
	for span in editor.spans {
		if enabled && span.end > selection.start && span.start < selection.end {
			append(&frame.surfaces, Surface{position = origin + [2]f32{min(span.leading, span.trailing), 0},
				size = {abs(span.trailing - span.leading), editor.metrics.height}, background = selection_color})
		}
	}
	_, result.error = fonts.draw(&active_state.text, frame.renderer, handle, edit.value(b), size, frame.scale, 0, origin, color, &frame.surfaces)
	if b.composing {
		for span in editor.spans {
			if span.end > b.marked.start && span.start < b.marked.end {
				append(&frame.surfaces, Surface{position = origin + [2]f32{min(span.leading, span.trailing), editor.metrics.height - 2},
					size = {abs(span.trailing - span.leading), 1}, background = color})
			}
		}
	}
	caret := Rect{origin + [2]f32{editor.caret_x, 0}, {1.5, editor.metrics.height}}
	if enabled && direct_focus() == id {
		if b.composing || math.mod(frame.time - editor.caret_time, 1.0) < 0.6 {
			append(&frame.surfaces, Surface{position = caret.position, size = caret.size, background = color})
		}
		caret.position.x = clamp(caret.position.x, r.position.x, r.position.x + r.size.x)
		request_text_input(edit.value(b), selection, caret, b.marked if b.composing else input.NO_TEXT_RANGE)
	}
	close_clip()
	result.composing, result.empty = b.composing, len(b.bytes) == 0
	result.changed = b.revision != revision
	return result
}

@(private) prepare_editor :: proc(editor: ^Text_Edit, font: Font, size: f32) -> Text_Error {
	scale := current_frame().scale
	if editor.catalog_generation == active_state.text.catalog_generation && editor.prepared && editor.prepared_revision == editor.buffer.revision && editor.font == font && editor.size == size && editor.scale == scale { return .None }
	metrics, err := fonts.caret_spans(&active_state.text, font, edit.value(&editor.buffer), size, scale, 0, &editor.spans)
	if err != .None { return err }
	editor.metrics = metrics
	editor.catalog_generation = active_state.text.catalog_generation
	editor.font, editor.size, editor.scale = font, size, scale
	editor.prepared_revision, editor.prepared = editor.buffer.revision, true
	editor.caret_x = caret_position(editor, editor.buffer.cursor)
	editor.caret_byte = editor.buffer.cursor
	return .None
}

// At a bidi boundary two visual positions can represent the same byte offset.
// Keyboard/pointer movement preserves the chosen edge; edits choose the leading
// edge of the following grapheme (or the final trailing edge).
@(private) caret_position :: proc(editor: ^Text_Edit, index: int) -> f32 {
	for span in editor.spans { if span.start == index { return span.leading } }
	for span in editor.spans { if span.end == index { return span.trailing } }
	return 0
}
@(private) hit_caret :: proc(editor: ^Text_Edit, x: f32) -> (int, f32) {
	return text_hit_test(editor.spans[:], x)
}
@(private) move_visual :: proc(editor: ^Text_Edit, right, extend: bool) {
	b := &editor.buffer
	range := edit.selection(b)
	if range.start != range.end && !extend {
		position := -max(f32) if right else max(f32)
		index := b.cursor
		for span in editor.spans {
			if span.end <= range.start || span.start >= range.end { continue }
			for edge in ([2]struct {index: int, x: f32}{{span.start, span.leading}, {span.end, span.trailing}}) {
				if (right && edge.x > position) || (!right && edge.x < position) { index, position = edge.index, edge.x }
			}
		}
		if abs(position) != max(f32) { b.cursor, b.anchor = index, index; editor.caret_byte, editor.caret_x = index, position; return }
	}
	current := editor.caret_x if b.cursor == editor.caret_byte else caret_position(editor, b.cursor)
	best: f32 = max(f32)
	index, position := b.cursor, current
	for span in editor.spans {
		for edge in ([2]struct {index: int, x: f32}{{span.start, span.leading}, {span.end, span.trailing}}) {
			distance := edge.x - current if right else current - edge.x
			if distance > 0.001 && distance < best { index, position, best = edge.index, edge.x, distance }
		}
	}
	b.cursor = index
	if !extend { b.anchor = index }
	editor.caret_byte, editor.caret_x = index, position
}
