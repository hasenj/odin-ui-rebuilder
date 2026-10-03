package text_input_check

import ui "../../core"
import edit "../../core/edit"
import "base:intrinsics"
import ns "core:sys/darwin/Foundation"
import "core:fmt"

buffer: edit.Buffer
stage: int
main :: proc() {
	edit.init(&buffer, "A😀Z")
	defer edit.destroy(&buffer)
	ui.open_window("Native text input check", 300, 160, update, transparent = false)
}
update :: proc() {
	ui.focusable(); ui.request_focus()
	for op in ui.current_frame().input.text.operations { edit.apply(&buffer, op) }
	view: ^ns.View
	window := intrinsics.objc_send(^ns.Window, ns.Application.sharedApplication(), "keyWindow")
	if window == nil { return }
	view = window->contentView()
	none := ns.Range{ns.UInteger(max(int)), 0}
	switch stage {
	case 0:
	case 1:
		selected := intrinsics.objc_send(ns.Range, view, "selectedRange")
		assert(selected == (ns.Range{4, 0}), "UTF-8 selection must become UTF-16 for AppKit")
		insert(view, "é", {1, 2}) // Replace the surrogate pair, not Z.
	case 2:
		assert(edit.value(&buffer) == "AéZ")
		mark(view, "に", {1, 0}, none)
		mark(view, "日本", {2, 0}, none)
		assert(intrinsics.objc_send(ns.BOOL, view, "hasMarkedText"))
		assert(intrinsics.objc_send(ns.Range, view, "markedRange") == (ns.Range{2, 2}))
	case 3:
		assert(edit.value(&buffer) == "Aé日本Z" && buffer.composing)
		insert(view, "日本語", none)
	case 4:
		assert(edit.value(&buffer) == "Aé日本語Z" && !buffer.composing)
		intrinsics.objc_send(nil, view, "doCommandBySelector:", intrinsics.objc_find_selector("moveToBeginningOfLine:"))
		insert(view, "X", none)
	case 5:
		assert(edit.value(&buffer) == "XAé日本語Z")
		mark(view, "仮", {1, 0}, none)
	case 6:
		assert(buffer.composing)
		intrinsics.objc_send(nil, window, "resignKeyWindow")
		intrinsics.objc_send(nil, window, "makeKeyWindow")
	case 7:
		assert(edit.value(&buffer) == "XAé日本語Z" && !buffer.composing)
		key(window, "\b", 51)
	case 8:
		assert(edit.value(&buffer) == "Aé日本語Z")
		assert(.Backspace in ui.current_frame().input.keys_pressed)
		assert(.Backspace in ui.current_frame().input.text.handled_keys)
		key(window, "z", 6, {.Command})
	case 9:
		assert(edit.value(&buffer) == "XAé日本語Z")
		ui.clear_focus()
	case 10:
		fmt.println("Verified native text client: UTF-16 ranges, repeated marked text, commit ordering, focus-loss cancellation and key interpretation/undo")
		ui.request_close(ui.current_window())
	}
	if stage != 9 {
		ui.request_text_input(edit.value(&buffer), edit.selection(&buffer), {{20, 30}, {2, 24}}, buffer.marked if buffer.composing else {-1, -1})
	}
	stage += 1
}
key :: proc(window: ^ns.Window, value: string, code: u16, flags: ns.EventModifierFlags = {}) {
	s := ns.String.alloc()->initWithOdinString(value); defer s->release()
	event := intrinsics.objc_send(^ns.Event, ns.Event,
		"keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:",
		ns.EventType.KeyDown, ns.Point{}, flags, ns.TimeInterval(0),
		intrinsics.objc_send(ns.Integer, window, "windowNumber"), cast(ns.id)nil, s, s, ns.BOOL(false), code)
	intrinsics.objc_send(nil, window, "sendEvent:", event)
}
insert :: proc(view: ^ns.View, value: string, replacement: ns.Range) {
	s := ns.String.alloc()->initWithOdinString(value); defer s->release()
	intrinsics.objc_send(nil, view, "insertText:replacementRange:", s, replacement)
}
mark :: proc(view: ^ns.View, value: string, selected, replacement: ns.Range) {
	s := ns.String.alloc()->initWithOdinString(value); defer s->release()
	intrinsics.objc_send(nil, view, "setMarkedText:selectedRange:replacementRange:", s, selected, replacement)
}
