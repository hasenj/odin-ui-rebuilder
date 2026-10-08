package ui

import "core:strings"
import edit "edit"

// Model values, not widget state. Strings own storage from the given allocator;
// byte arrays own their allocator. Neither pointer is retained across calls.
Text_Value :: union {^string, ^[dynamic]u8}

text_value :: proc(value: Text_Value) -> string {
	switch target in value {
	case ^string: assert(target != nil); return target^
	case ^[dynamic]u8: assert(target != nil); return string(target^[:])
	}
	panic("Missing text value")
}

@(private)
Bound_Editor :: struct {editor: Text_Edit, initialized: bool}
@(private)
destroy_bound_editor :: proc(s: ^Bound_Editor) { destroy_text_edit(&s.editor) }

// Owns editing state under the current rect identity. The caller owns only the
// committed value. IME preedit lives in the retained editor until committed.
edit_text :: proc(value: Text_Value, font: Font_Ref, size: f32 = 20, color: Color = {0.93, 0.95, 0.98, 1}, selection_color: Color = {0.18, 0.39, 0.68, 0.8}, align: Text_Align = .Start,
	allocator := context.allocator, enabled: bool = true, clear: bool = false) -> Text_Edit_Result {
	model_allocator := allocator
	current_frame()
	// Model allocation defaults to the caller's context, while UI state uses
	// the window's persistent allocator. A private identity leaves the caller's
	// typed state slot available; input/focus still belong to the current rect.
	context.allocator = active_state.allocator
	open_identity()
	s := state(Bound_Editor, cleanup = destroy_bound_editor)
	close_identity()
	before := text_value(value)
	external_change := s.initialized && before != committed_text(&s.editor)
	if !s.initialized || external_change || clear {
		anchor, cursor := s.editor.buffer.anchor, s.editor.buffer.cursor
		was_initialized := s.initialized
		destroy_text_edit(&s.editor)
		init_text_edit(&s.editor, "" if clear else before)
		if was_initialized && !clear { edit.select(&s.editor.buffer, anchor, cursor) }
		s.initialized = true
	}
	// Disabling a field cancels uncommitted input rather than modifying the model.
	if !enabled { edit.apply(&s.editor.buffer, {kind = .Cancel_Composition}) }
	result := edit_text_state(&s.editor, font, size, color, selection_color, align,
		enabled = enabled, accept_input = !external_change && !clear)
	committed := committed_text(&s.editor)
	result.changed = before != committed
	result.composing = s.editor.buffer.composing
	result.empty = len(s.editor.buffer.bytes) == 0
	if result.changed {
		switch target in value {
		case ^string:
			replacement := strings.clone(committed, model_allocator)
			delete(target^, model_allocator)
			target^ = replacement
		case ^[dynamic]u8:
			// resize uses the array's allocator; a zero-initialized array adopts
			// the explicitly supplied/default allocator on its first edit.
			if target.allocator.procedure == nil { target.allocator = model_allocator }
			resize(target, len(committed))
			copy(target^[:], transmute([]u8)committed)
		}
	}
	return result
}

@(private)
committed_text :: proc(editor: ^Text_Edit) -> string {
	b := &editor.buffer
	return b.composition.value if b.composing else edit.value(b)
}
