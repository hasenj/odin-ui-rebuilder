package demo15

import ui "../../core"
import "core:fmt"
import "core:os"

Field :: struct {editor: ui.Text_Edit, initialized: bool}
ids: [3]ui.Identity
editors: [3]^Field // Capture observations only; application state is identity-owned.
step: int
capture_mode: bool

main :: proc() {
	if len(os.args) > 1 && os.args[1] == "--capture" { capture_check(); return }
	ui.open_window("Text editing — Latin, Arabic and IME", 920, 640, update, transparent = false, frame_timing = .Summary)
}
update :: proc() {
	if _, ok := ui.find_font("UI"); !ok {
		_, err := ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf", "UI"); assert(err == .None)
		_, arabic_error := ui.load_font("examples/assets/fonts/Amiri-Regular.ttf", "Arabic"); assert(arabic_error == .None)
		_, discovery_error := ui.discover_fonts(); assert(discovery_error == .None)
		members := []ui.Font_Ref{"UI", "Arabic"}
		_, stack_error := ui.font_stack("Editor", members); assert(stack_error == .None)
	}
	ui.paint(color = {0.055, 0.075, 0.11, 1})
	ui.pad(32)
	ui.open_rect(.Top, 48); label("Text, now editable", 30); ui.close_rect()
	ui.open_rect(.Top, 55); label("Mix Latin, Arabic or Japanese in any field. Select, paste, undo, or use IME.", 16); ui.close_rect()
	for i in 0..<3 {
		ui.open_identity(key = i)
		ui.open_rect(.Top, 28)
		titles := [3]string{"LATIN / ACCENTS / LIGATURES", "ARABIC / MIXED DIRECTION", "JAPANESE / NATIVE IME"}
		label(titles[i], 13)
		ui.close_rect()
		ui.open_rect(.Top, 58)
		ids[i] = ui.current_identity()
		field := ui.state(Field, cleanup = destroy_field)
		editors[i] = field
		if !field.initialized {
			initials := [3]string{"Office café — select me and start typing", "مرحبا بالعالم — Hello 123", "日本語を入力してください"}
			initial := initials[i]
			ui.init_text_edit(&field.editor, initial); field.initialized = true
		}
		if i == 0 && !capture_mode && ui.current_frame().time < 0.1 { ui.request_focus() }
		if capture_mode && step == 0 && i == 0 { ui.request_focus() }
		ui.paint(color = {0.20, 0.48, 0.58, 1} if ui.focused() else {0.20, 0.25, 0.33, 1}, corners = 8)
		ui.pad(2); ui.paint(color = {0.095, 0.13, 0.18, 1}, corners = 6); ui.pad2(4, 12)
		font := "Editor"
		result := ui.edit_text(&field.editor, font, size = 24)
		if capture_mode { assert(result.error == .None) }
		if result.error != .None { label(fmt.tprintf("Font: %v (editing remains available)", result.error), 14) }
		ui.close_rect()
		ui.open_rect(.Top, 30)
		label(fmt.tprintf("%d bytes  /  cursor %d  /  %s", len(ui.text_edit_value(&field.editor)), field.editor.buffer.cursor,
			"composing" if field.editor.buffer.composing else "ready"), 12)
		ui.close_rect()
		ui.pad4(16, 0, 0, 0)
		ui.close_identity()
	}
	undo := "Command-Z" if ODIN_OS == .Darwin else "Control-Z"
	label(fmt.tprintf("Enter submits a line. Escape cancels composition. %s undoes an edit.", undo), 14)
}
label :: proc(value: string, size: f32) {
	_, err := ui.text(value, "UI", size = size, color = {0.84, 0.89, 0.95, 1}); assert(err == .None)
}
destroy_field :: proc(field: ^Field) { ui.destroy_text_edit(&field.editor) }

capture_check :: proc() {
	capture_mode = true
	frames: [12]ui.Capture_Frame
	for &frame, i in frames { frame = {size = {920, 640}, scale = 2, time = f64(i) / 10} }
	frames[0].path = "bin/demo15-initial.png"
	frames[2].path = "bin/demo15-selection.png"
	frames[5].path = "bin/demo15-composition.png"
	frames[6].path = "bin/demo15-committed.png"
	frames[10].path = "bin/demo15-fallback.png"
	frames[11].path = "bin/demo15-tofu.png"
	frames[8].path = "bin/demo15-narrow.png"; frames[8].size = {480, 640}
	result := ui.capture_frames(capture_update, frames[:]); assert(result.error == .None)
	fmt.println("Verified text editor capture: selection, ordered edits, composition, commit, undo and caret reveal")
}
capture_update :: proc() {
	ops: [2]ui.Text_Operation
	count := 0
	target := ids[0]
	switch step {
	case 1: ops[0] = {kind = .Command, command = .Select_All}; count = 1
	case 2:
		ops[0] = {kind = .Commit, text = "office cafe\u0301"}
		ops[1] = {kind = .Command, command = .Left, extend = true}; count = 2
	case 3: ops[0] = {kind = .Command, command = .Backspace}; count = 1
	case 4: target = ids[2]; ui.request_focus(target); ops[0] = {kind = .Command, command = .Select_All}; count = 1
	case 5: target = ids[2]; ops[0] = {kind = .Mark, text = "にほん", selection = {9, 9}}; count = 1
	case 6: target = ids[2]; ops[0] = {kind = .Commit, text = "日本語"}; count = 1
	case 7: target = ids[2]; ops[0] = {kind = .Command, command = .Undo}; count = 1
	case 8: target = ids[0]; ui.request_focus(target); ops[0] = {kind = .Commit, text = " — a long line whose caret must stay visible when the window becomes narrow"}; count = 1
	case 10:
		ops[0] = {kind = .Command, command = .Select_All}
		ops[1] = {kind = .Commit, text = "Hello 日本語 مرحبا — café"}; count = 2
	case 11:
		ops[0] = {kind = .Command, command = .Select_All}
		ops[1] = {kind = .Commit, text = "Before \U0010ffff after — 日本語 مرحبا"}; count = 2
	case:
	}
	ui.current_frame().input.text = {target = ui.text_target(target), operations = ops[:count]}
	update()
	if step == 3 { assert(ui.text_edit_value(&editors[0].editor) == "office caf") }
	if step == 5 { assert(editors[2].editor.buffer.composing) }
	if step == 6 { assert(ui.text_edit_value(&editors[2].editor) == "日本語" && !editors[2].editor.buffer.composing) }
	if step == 7 { assert(ui.text_edit_value(&editors[2].editor) == "日本語を入力してください") }
	if step == 8 { assert(editors[0].editor.scroll > 0) }
	if step == 10 { assert(ui.text_edit_value(&editors[0].editor) == "Hello 日本語 مرحبا — café") }
	if step == 11 { assert(ui.text_edit_value(&editors[0].editor) == "Before \U0010ffff after — 日本語 مرحبا") }
	step += 1
}
