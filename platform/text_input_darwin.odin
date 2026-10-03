package platform

import "../core/input"
import edit "../core/edit"
import "core:strings"
import "base:intrinsics"
import ns "core:sys/darwin/Foundation"

@(private) Mac_Text_Input :: struct {
	client: input.Text_Client,
	mirror: edit.Buffer,
	pending, snapshot: [dynamic]input.Text_Operation,
	pending_target: u64,
	handled: input.Keys,
	syncing, declined: bool,
}

@(private) macos_text_sync :: proc(renderer: ^Metal_Renderer, client: input.Text_Client) {
	t := &renderer.text_input
	if t.client.target == 0 && client.target == 0 { return }
	if t.client.target != client.target {
		t.syncing = true
		ctx := intrinsics.objc_send(ns.id, renderer.view, "inputContext")
		intrinsics.objc_send(nil, cast(^ns.Object)ctx, "discardMarkedText")
		t.syncing = false
		edit.destroy(&t.mirror)
		edit.init(&t.mirror, client.value)
	}
	t.client = client
	// Events delivered during this update already advanced the native mirror.
	// Do not overwrite them with the older core snapshot.
	if len(t.pending) > 0 && t.pending_target == client.target { t.client.value = ""; return }
	if t.mirror.composing && !client.has_marked {
		edit.finish_composition(&t.mirror)
		t.syncing = true
		intrinsics.objc_send(nil, intrinsics.objc_send(^ns.Object, renderer.view, "inputContext"), "discardMarkedText")
		t.syncing = false
	}
	// Keep native queries usable between updates without borrowing app storage.
	if edit.value(&t.mirror) != client.value {
		clear(&t.mirror.bytes); append(&t.mirror.bytes, ..transmute([]u8)client.value)
	}
	t.mirror.anchor, t.mirror.cursor = client.selection.start, client.selection.end
	t.mirror.marked = client.marked if client.has_marked else input.NO_TEXT_RANGE
	// Composition bookkeeping is owned by mirror's operations, not copied.
	t.client.value = ""
	ctx := intrinsics.objc_send(ns.id, renderer.view, "inputContext")
	intrinsics.objc_send(nil, cast(^ns.Object)ctx, "invalidateCharacterCoordinates")
}

@(private) clear_text_operations :: proc(ops: ^[dynamic]input.Text_Operation) {
	for op in ops^ { delete(op.text) }; clear(ops)
}
@(private) destroy_macos_text :: proc(t: ^Mac_Text_Input) {
	clear_text_operations(&t.pending); clear_text_operations(&t.snapshot)
	delete(t.pending); delete(t.snapshot); edit.destroy(&t.mirror)
}
@(private) sample_macos_text :: proc(renderer: ^Metal_Renderer) {
	t := &renderer.text_input
	clear_text_operations(&t.snapshot)
	t.snapshot, t.pending = t.pending, t.snapshot
	if renderer.input_state != nil {
		renderer.input_state.text = {target = t.pending_target, operations = t.snapshot[:], handled_keys = t.handled}
	}
	t.handled = {}
}
@(private) enqueue_text :: proc(renderer: ^Metal_Renderer, operation: input.Text_Operation) {
	t := &renderer.text_input
	if t.syncing || t.client.target == 0 { return }
	t.pending_target = t.client.target
	op := operation
	op.target = t.client.target
	op.text = strings.clone(op.text)
	append(&t.pending, op)
	edit.apply(&t.mirror, op)
}
@(private) macos_text_cancel :: proc(renderer: ^Metal_Renderer) {
	t := &renderer.text_input
	if t.client.target == 0 { return }
	if t.mirror.composing { enqueue_text(renderer, {kind = .Cancel_Composition}) }
	t.syncing = true
	intrinsics.objc_send(nil, intrinsics.objc_send(^ns.Object, renderer.view, "inputContext"), "discardMarkedText")
	t.syncing = false
}

@(private) macos_text_key :: proc(renderer: ^Metal_Renderer, event: ^ns.Event) {
	t := &renderer.text_input
	if t.client.target == 0 { return }
	key, known := macos_key(event->keyCode())
	t.declined = false
	if known && .Super in renderer.keyboard.modifiers {
		command: input.Text_Command
		matched := true
		#partial switch key {
		case .A: command = .Select_All
		case .C: command = .Copy
		case .X: command = .Cut
		case .V: command = .Paste
		case .Z: command = .Redo if .Shift in renderer.keyboard.modifiers else .Undo
		case: matched = false
		}
		if matched {
			enqueue_text(renderer, {kind = .Command, command = command})
			t.handled += {key}
			return
		}
	}
	array := intrinsics.objc_send(^ns.Array, ns.Array, "arrayWithObject:", event)
	intrinsics.objc_send(nil, renderer.view, "interpretKeyEvents:", array)
	if known && !t.declined { t.handled += {key} }
}

@(private) native_text :: proc(raw_object: ns.id) -> string {
	object := cast(^ns.Object)raw_object
	if intrinsics.objc_send(ns.BOOL, object, "isKindOfClass:", intrinsics.objc_find_class("NSAttributedString")) {
		object = intrinsics.objc_send(^ns.Object, object, "string")
	}
	return (cast(^ns.String)object)->odinString()
}
@(private) utf16_index :: proc(value: string, byte_index: int) -> ns.UInteger {
	result: ns.UInteger
	for r, i in value { if i >= byte_index { break }; result += 2 if r > 0xffff else 1 }
	return result
}
@(private) utf8_index :: proc(value: string, index: ns.UInteger) -> int {
	count: ns.UInteger
	for r, i in value { if count >= index { return i }; count += 2 if r > 0xffff else 1 }
	return len(value)
}
@(private) native_range :: proc(value: string, range: input.Text_Range) -> ns.Range {
	if range.start < 0 { return {ns.UInteger(max(int)), 0} }
	lo, hi := utf16_index(value, range.start), utf16_index(value, range.end)
	return {lo, hi - lo}
}
@(private) byte_range :: proc(value: string, range: ns.Range) -> input.Text_Range {
	if range.location >= ns.UInteger(max(int)) { return input.NO_TEXT_RANGE }
	return {utf8_index(value, range.location), utf8_index(value, range.location + min(range.length, ns.UInteger(max(int)) - range.location))}
}

@(private) text_insert :: proc "c" (self: ns.id, _: ns.SEL, text: ns.id, replacement: ns.Range) {
	r := metal_view_renderer(self); if r == nil { return }; context = r.odin_context
	range := byte_range(edit.value(&r.text_input.mirror), replacement)
	enqueue_text(r, {kind = .Commit, text = native_text(text), replacement = range, has_replacement = range.start >= 0})
}
@(private) text_mark :: proc "c" (self: ns.id, _: ns.SEL, text: ns.id, selection, replacement: ns.Range) {
	r := metal_view_renderer(self); if r == nil { return }; context = r.odin_context
	value := native_text(text)
	range := byte_range(edit.value(&r.text_input.mirror), replacement)
	enqueue_text(r, {kind = .Mark, text = value, replacement = range, has_replacement = range.start >= 0, selection = byte_range(value, selection)})
}
@(private) text_unmark :: proc "c" (self: ns.id, _: ns.SEL) {
	r := metal_view_renderer(self); if r == nil { return }; context = r.odin_context
	enqueue_text(r, {kind = .Unmark})
}
@(private) text_has_marked :: proc "c" (self: ns.id, _: ns.SEL) -> ns.BOOL {
	r := metal_view_renderer(self); if r == nil { return false }; context = r.odin_context
	return ns.BOOL(r.text_input.client.target != 0 && r.text_input.mirror.marked.start >= 0)
}
@(private) text_marked_range :: proc "c" (self: ns.id, _: ns.SEL) -> ns.Range {
	r := metal_view_renderer(self); if r == nil { return {ns.UInteger(max(int)), 0} }; context = r.odin_context
	return native_range(edit.value(&r.text_input.mirror), r.text_input.mirror.marked)
}
@(private) text_selected_range :: proc "c" (self: ns.id, _: ns.SEL) -> ns.Range {
	r := metal_view_renderer(self); if r == nil { return {ns.UInteger(max(int)), 0} }; context = r.odin_context
	return native_range(edit.value(&r.text_input.mirror), edit.selection(&r.text_input.mirror))
}
@(private) text_valid_attributes :: proc "c" (_: ns.id, _: ns.SEL) -> ^ns.Array {
	return intrinsics.objc_send(^ns.Array, ns.Array, "array")
}
@(private) text_substring :: proc "c" (self: ns.id, _: ns.SEL, proposed: ns.Range, actual: ^ns.Range) -> ns.id {
	r := metal_view_renderer(self); if r == nil { return nil }; context = r.odin_context
	value := edit.value(&r.text_input.mirror)
	range := byte_range(value, proposed)
	if range.start < 0 { return nil }
	if actual != nil { actual^ = native_range(value, range) }
	text := ns.String.alloc()->initWithOdinString(value[range.start:range.end])
	defer text->release()
	object := intrinsics.objc_send(^ns.Object, cast(^ns.Object)intrinsics.objc_find_class("NSAttributedString"), "alloc")
	object = intrinsics.objc_send(^ns.Object, object, "initWithString:", text)
	return intrinsics.objc_send(ns.id, object, "autorelease")
}
@(private) text_first_rect :: proc "c" (self: ns.id, _: ns.SEL, _: ns.Range, actual: ^ns.Range) -> ns.Rect {
	r := metal_view_renderer(self); if r == nil { return {} }; context = r.odin_context
	client := r.text_input.client
	if actual != nil { actual^ = native_range(edit.value(&r.text_input.mirror), edit.selection(&r.text_input.mirror)) }
	bounds := r.view->bounds()
	y := ns.Float(client.caret_position.y)
	if !r.view->isFlipped() { y = bounds.size.height - y - ns.Float(client.caret_size.y) }
	rect := ns.Rect{origin = {ns.Float(client.caret_position.x), y}, size = {ns.Float(max(1, client.caret_size.x)), ns.Float(max(1, client.caret_size.y))}}
	rect = intrinsics.objc_send(ns.Rect, r.view, "convertRect:toView:", rect, rawptr(nil))
	return intrinsics.objc_send(ns.Rect, r.window, "convertRectToScreen:", rect)
}
@(private) text_index_for_point :: proc "c" (self: ns.id, _: ns.SEL, _: ns.Point) -> ns.UInteger {
	// Candidate placement is caret-based in this first adapter. Fine-grained
	// native character queries can later use the editor's complete geometry.
	r := metal_view_renderer(self); if r == nil { return ns.UInteger(max(int)) }; context = r.odin_context
	return utf16_index(edit.value(&r.text_input.mirror), r.text_input.mirror.cursor)
}

@(private) text_command :: proc "c" (self: ns.id, _: ns.SEL, selector: ns.SEL) {
	r := metal_view_renderer(self); if r == nil { return }; context = r.odin_context
	name := string(ns.sel_getName(selector))
	command: input.Text_Command
	extend := strings.contains(name, "AndModifySelection")
	switch name {
	case "moveLeft:", "moveBackward:", "moveLeftAndModifySelection:", "moveBackwardAndModifySelection:": command = .Left
	case "moveRight:", "moveForward:", "moveRightAndModifySelection:", "moveForwardAndModifySelection:": command = .Right
	case "moveWordLeft:", "moveWordBackward:", "moveWordLeftAndModifySelection:", "moveWordBackwardAndModifySelection:": command = .Word_Left
	case "moveWordRight:", "moveWordForward:", "moveWordRightAndModifySelection:", "moveWordForwardAndModifySelection:": command = .Word_Right
	case "moveToBeginningOfLine:", "moveToBeginningOfDocument:", "moveToBeginningOfLineAndModifySelection:", "moveToBeginningOfDocumentAndModifySelection:", "moveUp:": command = .Home
	case "moveToEndOfLine:", "moveToEndOfDocument:", "moveToEndOfLineAndModifySelection:", "moveToEndOfDocumentAndModifySelection:", "moveDown:": command = .End
	case "deleteBackward:": command = .Backspace
	case "deleteForward:": command = .Delete
	case "deleteWordBackward:": command = .Delete_Word_Backward
	case "deleteWordForward:": command = .Delete_Word_Forward
	case "selectAll:": command = .Select_All
	case "copy:": command = .Copy
	case "cut:": command = .Cut
	case "paste:": command = .Paste
	case "undo:": command = .Undo
	case "redo:": command = .Redo
	case "insertNewline:", "insertLineBreak:": command = .Submit
	case "cancelOperation:": command = .Cancel
	case: r.text_input.declined = true; return
	}
	enqueue_text(r, {kind = .Command, command = command, extend = extend})
}

@(private) install_text_client :: proc(cls: ns.Class) {
	assert(ns.class_addProtocol(cls, ns.objc_getProtocol("NSTextInputClient")))
	for method in ([?]struct {name: cstring, impl: rawptr, encoding: cstring}{
		{"insertText:replacementRange:", rawptr(text_insert), "v@:@{_NSRange=QQ}"},
		{"setMarkedText:selectedRange:replacementRange:", rawptr(text_mark), "v@:@{_NSRange=QQ}{_NSRange=QQ}"},
		{"unmarkText", rawptr(text_unmark), "v@:"},
		{"hasMarkedText", rawptr(text_has_marked), "B@:"},
		{"markedRange", rawptr(text_marked_range), "{_NSRange=QQ}@:"},
		{"selectedRange", rawptr(text_selected_range), "{_NSRange=QQ}@:"},
		{"validAttributesForMarkedText", rawptr(text_valid_attributes), "@@:"},
		{"attributedSubstringForProposedRange:actualRange:", rawptr(text_substring), "@@:{_NSRange=QQ}^{_NSRange=QQ}"},
		{"firstRectForCharacterRange:actualRange:", rawptr(text_first_rect), "{CGRect={CGPoint=dd}{CGSize=dd}}@:{_NSRange=QQ}^{_NSRange=QQ}"},
		{"characterIndexForPoint:", rawptr(text_index_for_point), "Q@:{CGPoint=dd}"},
		{"doCommandBySelector:", rawptr(text_command), "v@::"},
	}) { assert(ns.class_addMethod(cls, ns.sel_registerName(method.name), cast(ns.IMP)method.impl, method.encoding)) }
}

@(private) pasteboard_type :: proc() -> ^ns.String {
	return ns.String.alloc()->initWithOdinString("public.utf8-plain-text")
}
@(private) macos_clipboard_read :: proc() -> (string, bool) {
	ns.scoped_autoreleasepool()
	board := intrinsics.objc_send(^ns.Pasteboard, ns.Pasteboard, "generalPasteboard")
	kind := pasteboard_type(); defer kind->release()
	value := intrinsics.objc_send(^ns.String, board, "stringForType:", kind)
	if value == nil { return "", false }
	return strings.clone(value->odinString()), true
}
@(private) macos_clipboard_write :: proc(value: string) -> bool {
	ns.scoped_autoreleasepool()
	board := intrinsics.objc_send(^ns.Pasteboard, ns.Pasteboard, "generalPasteboard")
	kind := pasteboard_type(); defer kind->release()
	text := ns.String.alloc()->initWithOdinString(value); defer text->release()
	intrinsics.objc_send(ns.Integer, board, "clearContents")
	return bool(intrinsics.objc_send(ns.BOOL, board, "setString:forType:", text, kind))
}
