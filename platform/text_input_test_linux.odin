package platform

import "core:testing"
import "core:strings"
import "core:sys/posix"
import "core:time"
import "../core/input"
import edit "../core/edit"

@(test)
wayland_text_pipeline :: proc(t: ^testing.T) {
	w := Wayland_Window{odin_context = context, keyboard_focused = true}
	defer destroy_wayland_text(&w)
	defer destroy_wayland_keyboard(&w)
	w.xkb_context = xkb_context_new(0)
	w.xkb_keymap = xkb_keymap_new_from_names(w.xkb_context, nil, 0)
	w.xkb_state = xkb_state_new(w.xkb_keymap)
	w.held_keys = make(map[u32]input.Key)
	wayland_text_sync(&w, {target = 7, value = "", marked = input.NO_TEXT_RANGE})
	keyboard_key(&w, nil, 1, 0, 30, 1) // A, layout translated.
	keyboard_key(&w, nil, 2, 0, 30, 0)
	keyboard_key(&w, nil, 3, 0, 48, 1) // B in same snapshot.
	keyboard_key(&w, nil, 4, 0, 48, 0)
	snapshot := take_wayland_input(&w)
	testing.expect_value(t, len(snapshot.text.operations), 2)
	testing.expect_value(t, snapshot.text.operations[0].text, "a")
	testing.expect_value(t, snapshot.text.operations[1].text, "b")
	testing.expect(t, snapshot.text.handled_keys == input.Keys{.A, .B})
	testing.expect_value(t, len(take_wayland_input(&w).text.operations), 0)
	// Compose/dead keys use XKB even without a compositor IME.
	assert(w.text_input.compose != nil)
	xkb_compose_state_feed(w.text_input.compose, 0xfe51) // dead_acute
	wayland_text_key(&w, 18) // e
	snapshot = take_wayland_input(&w)
	testing.expect_value(t, snapshot.text.operations[0].text, "é")
	w.keyboard.modifiers = {.Control}
	wayland_text_key(&w, 30)
	snapshot = take_wayland_input(&w)
	testing.expect_value(t, snapshot.text.operations[0].command, input.Text_Command.Select_All)
	w.keyboard.modifiers = {}

	wayland_text_sync(&w, {target = 8, value = "hello", selection = {5, 5}, marked = input.NO_TEXT_RANGE})
	w.text_input.entered, w.text_input.enabled = true, true
	w.text_input.serial, w.text_input.enabled_serial = 3, 3
	text_preedit(&w, nil, "に", 3, 3)
	testing.expect_value(t, len(w.text_input.pending), 0) // Double-buffer until done.
	text_done(&w, nil, 3)
	snapshot = take_wayland_input(&w)
	testing.expect_value(t, snapshot.text.operations[0].kind, input.Text_Operation_Kind.Mark)
	testing.expect_value(t, edit.value(&w.text_input.mirror), "helloに")
	text_done(&w, nil, 3) // An acknowledgement must not erase composition.
	testing.expect(t, w.text_input.mirror.composing)
	wayland_text_key(&w, 18)
	testing.expect_value(t, len(w.text_input.pending), 0) // No XKB duplicate during IME composition.
	text_commit(&w, nil, "日本")
	text_preedit(&w, nil, "", 0, 0)
	text_done(&w, nil, 3)
	snapshot = take_wayland_input(&w)
	testing.expect_value(t, len(snapshot.text.operations), 1)
	testing.expect_value(t, edit.value(&w.text_input.mirror), "hello日本")
	testing.expect(t, !w.text_input.mirror.composing)
	text_preedit(&w, nil, "x", 1, 1); text_done(&w, nil, 3)
	text_leave(&w, nil, nil)
	snapshot = take_wayland_input(&w)
	testing.expect_value(t, snapshot.text.operations[len(snapshot.text.operations)-1].kind, input.Text_Operation_Kind.Cancel_Composition)
	testing.expect_value(t, edit.value(&w.text_input.mirror), "hello日本")

	// Old text remains tagged with its original identity when focus changes.
	wayland_text_enqueue(&w, {kind = .Commit, text = "!"})
	wayland_text_sync(&w, {target = 9, value = "new", selection = {3, 3}, marked = input.NO_TEXT_RANGE})
	snapshot = take_wayland_input(&w)
	testing.expect_value(t, snapshot.text.operations[0].target, u64(8))
	testing.expect_value(t, edit.value(&w.text_input.mirror), "new")
	w.text_input.entered, w.text_input.enabled = true, true
	w.text_input.serial, w.text_input.enabled_serial = 5, 5
	text_commit(&w, nil, "stale"); text_done(&w, nil, 3)
	testing.expect_value(t, len(w.text_input.pending), 0)
	// UTF-8 surrounding deletion around a selected span, followed by replacement.
	w.text_input.enabled = false
	wayland_text_sync(&w, {target = 9, value = "aébcd", selection = {3, 4}, marked = input.NO_TEXT_RANGE})
	w.text_input.enabled = true
	text_delete(&w, nil, 2, 1); text_commit(&w, nil, "X"); text_done(&w, nil, 5)
	testing.expect_value(t, edit.value(&w.text_input.mirror), "aXd")
	w.text_input.enabled = false
}

@(test)
wayland_clipboard_pipe :: proc(t: ^testing.T) {
	// Large transfers must yield when the pipe fills and finish byte-for-byte.
	fds: [2]posix.FD
	assert(posix.pipe(&fds) == nil)
	defer posix.close(fds[0])
	posix.fcntl(fds[0], .SETFL, posix.O_NONBLOCK)
	posix.fcntl(fds[1], .SETFL, posix.O_NONBLOCK)
	value := strings.repeat("clipboard 日本\n", 20000)
	defer delete(value)
	append(&clipboard_writes, Clipboard_Write{fd = fds[1], text = strings.clone(value), start = time.tick_now()})
	defer shutdown_wayland_clipboard()
	bytes: [dynamic]u8
	defer delete(bytes)
	for {
		flush_clipboard_writes()
		buffer: [4096]u8
		n := posix.read(fds[0], raw_data(buffer[:]), len(buffer))
		if n == 0 { break }
		if n > 0 { append(&bytes, ..buffer[:n]) }
	}
	testing.expect_value(t, string(bytes[:]), value)
	// A disappearing paste receiver must not terminate the application.
	closed_fds: [2]posix.FD
	assert(posix.pipe(&closed_fds) == nil)
	posix.close(closed_fds[0])
	defer posix.close(closed_fds[1])
	testing.expect(t, clipboard_pipe_write(closed_fds[1], transmute([]u8)string("cancelled")) < 0)
}
