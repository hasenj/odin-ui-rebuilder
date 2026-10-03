package platform

import "core:strings"
import "core:os"
import "core:math"
import "../core/input"
import edit "../core/edit"

@(private)
Wayland_Text_Input :: struct {
	manager, proxy, compose_table, compose: rawptr,
	client: input.Text_Client,
	mirror: edit.Buffer,
	pending, snapshot: [dynamic]input.Text_Operation,
	handled: input.Keys,
	entered, enabled, dirty, awaiting_done, ime_change: bool,
	serial, enabled_serial: u32,
	preedit, commit: string,
	selection: input.Text_Range,
	before, after: u32,
	got_preedit, got_commit, got_delete: bool,
}

foreign import xkb_text "system:xkbcommon"
foreign xkb_text {
	xkb_state_key_get_utf8 :: proc(state: rawptr, key: u32, buffer: [^]u8, size: uintptr) -> i32 ---
	xkb_state_key_get_one_sym :: proc(state: rawptr, key: u32) -> u32 ---
	xkb_compose_table_new_from_locale :: proc(ctx: rawptr, locale: cstring, flags: u32) -> rawptr ---
	xkb_compose_table_unref :: proc(table: rawptr) ---
	xkb_compose_state_new :: proc(table: rawptr, flags: u32) -> rawptr ---
	xkb_compose_state_unref :: proc(state: rawptr) ---
	xkb_compose_state_feed :: proc(state: rawptr, sym: u32) -> i32 ---
	xkb_compose_state_get_status :: proc(state: rawptr) -> u32 ---
	xkb_compose_state_get_utf8 :: proc(state: rawptr, buffer: [^]u8, size: uintptr) -> i32 ---
	xkb_compose_state_reset :: proc(state: rawptr) ---
}

@(private)
ensure_wayland_text :: proc(w: ^Wayland_Window) {
	t := &w.text_input
	if t.manager == nil || w.seat == nil || t.proxy != nil { return }
	t.proxy = wl_construct(t.manager, 1, &zwp_text_input_v3_interface, []WL_Argument{{o = nil}, {o = w.seat}})
	wl_listen(t.proxy, &text_listener, w)
}

@(private)
clear_wayland_text_operations :: proc(ops: ^[dynamic]input.Text_Operation) {
	for op in ops^ { delete(op.text) }; clear(ops)
}
@(private)
reset_text_batch :: proc(t: ^Wayland_Text_Input) {
	delete(t.preedit); delete(t.commit)
	t.preedit, t.commit = "", ""
	t.got_preedit, t.got_commit, t.got_delete = false, false, false
	t.before, t.after = 0, 0
}
@(private)
destroy_wayland_text :: proc(w: ^Wayland_Window) {
	t := &w.text_input
	wl_release(t.proxy, 0); wl_release(t.manager, 0)
	if t.compose != nil { xkb_compose_state_unref(t.compose) }
	if t.compose_table != nil { xkb_compose_table_unref(t.compose_table) }
	clear_wayland_text_operations(&t.pending); clear_wayland_text_operations(&t.snapshot)
	delete(t.pending); delete(t.snapshot); edit.destroy(&t.mirror); reset_text_batch(t)
	t^ = {}
}
@(private)
wayland_text_enqueue :: proc(w: ^Wayland_Window, operation: input.Text_Operation) {
	t := &w.text_input
	if t.client.target == 0 { return }
	op := operation; op.target = t.client.target; op.text = strings.clone(op.text)
	append(&t.pending, op)
	edit.apply(&t.mirror, op)
	t.dirty = true
}
@(private)
sample_wayland_text :: proc(w: ^Wayland_Window) {
	t := &w.text_input
	clear_wayland_text_operations(&t.snapshot)
	t.snapshot, t.pending = t.pending, t.snapshot
	w.input.text = {target = t.client.target, operations = t.snapshot[:], handled_keys = t.handled}
	t.handled = {}
}
@(private)
wayland_text_cancel :: proc(w: ^Wayland_Window) {
	t := &w.text_input
	if t.mirror.composing { wayland_text_enqueue(w, {kind = .Cancel_Composition}) }
	if t.compose != nil { xkb_compose_state_reset(t.compose) }
	reset_text_batch(t)
}
@(private)
text_protocol_commit :: proc(t: ^Wayland_Text_Input) {
	wl_request(t.proxy, 7); t.serial += 1
}
@(private)
wayland_text_sync :: proc(w: ^Wayland_Window, client: input.Text_Client) {
	t := &w.text_input
	changed_target := t.client.target != client.target
	if changed_target {
		if t.enabled { wl_request(t.proxy, 2); text_protocol_commit(t); t.enabled = false }
		wayland_text_cancel(w)
		edit.destroy(&t.mirror); edit.init(&t.mirror, client.value)
		t.dirty = true; t.awaiting_done = false; t.ime_change = false
	}
	if t.client.caret_position != client.caret_position || t.client.caret_size != client.caret_size { t.dirty = true }
	t.client = client; t.client.value = ""
	// Keep event-owned text until the core has received its snapshot.
	pending := false
	for op in t.pending { if op.target == client.target { pending = true; break } }
	if !pending {
		if edit.value(&t.mirror) != client.value || edit.selection(&t.mirror) != client.selection || t.mirror.marked != client.marked {
			t.dirty = true; t.ime_change = false
		}
		if t.mirror.composing && !client.has_marked { edit.finish_composition(&t.mirror) }
		clear(&t.mirror.bytes); append(&t.mirror.bytes, ..transmute([]u8)client.value)
		edit.select(&t.mirror, client.selection.start, client.selection.end)
		t.mirror.marked = client.marked if client.has_marked else input.NO_TEXT_RANGE
	}
	publish_wayland_text(w)
}

// Surrounding text excludes preedit and stays within the protocol's 4000-byte
// message limit. Keep a complete selection or omit surrounding-text support.
@(private)
text_surrounding :: proc(t: ^Wayland_Text_Input) -> (string, i32, i32, bool) {
	value := edit.value(&t.mirror)
	cursor, anchor := t.mirror.cursor, t.mirror.anchor
	if t.mirror.marked.start >= 0 {
		r := t.mirror.marked
		value = strings.concatenate({value[:r.start], value[r.end:]}, context.temp_allocator)
		cursor, anchor = r.start, r.start
	}
	lo, hi := min(cursor, anchor), max(cursor, anchor)
	if hi - lo > 4000 { return "", 0, 0, false }
	start := max(0, lo - (4000 - (hi - lo)) / 2)
	for start > 0 && start < len(value) && value[start] & 0xc0 == 0x80 { start += 1 }
	end := min(len(value), start + 4000)
	for end < len(value) && end > start && value[end] & 0xc0 == 0x80 { end -= 1 }
	return value[start:end], i32(cursor - start), i32(anchor - start), true
}
@(private)
publish_wayland_text :: proc(w: ^Wayland_Window) {
	t := &w.text_input
	if t.proxy == nil || !t.entered { return }
	if t.client.target == 0 {
		if t.enabled { wl_request(t.proxy, 2); text_protocol_commit(t); t.enabled = false }
		return
	}
	if t.awaiting_done { return }
	if !t.enabled {
		wl_request(t.proxy, 1)
		wl_request(t.proxy, 5, []WL_Argument{{u = 0}, {u = 0}})
		t.enabled = true; t.dirty = true; t.enabled_serial = t.serial + 1
	}
	if !t.dirty { return }
	value, cursor, anchor, ok := text_surrounding(t)
	if ok {
		text := strings.clone_to_cstring(value, context.temp_allocator)
		wl_request(t.proxy, 3, []WL_Argument{{s = text}, {i = cursor}, {i = anchor}})
	}
	wl_request(t.proxy, 4, []WL_Argument{{u = 0 if t.ime_change else 1}})
	p, size := t.client.caret_position, t.client.caret_size
	wl_request(t.proxy, 6, []WL_Argument{{i = i32(math.floor(p.x))}, {i = i32(math.floor(p.y))}, {i = i32(max(1, math.ceil(size.x)))}, {i = i32(max(1, math.ceil(size.y)))}})
	text_protocol_commit(t); t.dirty = false; t.ime_change = false
}

@(private)
text_enter :: proc "c" (data, _: rawptr, surface: rawptr) {
	w := cast(^Wayland_Window)data; context = w.odin_context
	if surface != w.surface { return }
	w.text_input.entered = true; w.text_input.awaiting_done = false; publish_wayland_text(w)
}
@(private)
text_leave :: proc "c" (data, _: rawptr, surface: rawptr) {
	w := cast(^Wayland_Window)data; context = w.odin_context
	if surface != w.surface { return }
	w.text_input.entered, w.text_input.enabled, w.text_input.awaiting_done = false, false, false
	wayland_text_cancel(w)
}
@(private)
text_preedit :: proc "c" (data, _: rawptr, text: cstring, begin, end: i32) {
	w := cast(^Wayland_Window)data; context = w.odin_context; t := &w.text_input
	delete(t.preedit); t.preedit = strings.clone(string(text)); t.got_preedit = true
	t.selection = {int(begin), int(end)}
}
@(private)
text_commit :: proc "c" (data, _: rawptr, text: cstring) {
	w := cast(^Wayland_Window)data; context = w.odin_context; t := &w.text_input
	delete(t.commit); t.commit = strings.clone(string(text)); t.got_commit = true
}
@(private)
text_delete :: proc "c" (data, _: rawptr, before, after: u32) {
	w := cast(^Wayland_Window)data
	w.text_input.before, w.text_input.after, w.text_input.got_delete = before, after, true
}
@(private)
text_done :: proc "c" (data, _: rawptr, serial: u32) {
	w := cast(^Wayland_Window)data; context = w.odin_context; t := &w.text_input
	defer reset_text_batch(t)
	if !t.entered || !t.enabled || i32(serial - t.enabled_serial) < 0 { return }
	t.awaiting_done = serial != t.serial
	// Bare acknowledgements must not erase an in-progress preedit.
	if !t.got_preedit && !t.got_commit && !t.got_delete { return }
	if t.got_delete && (t.before > 0 || t.after > 0) {
		if t.mirror.composing { wayland_text_enqueue(w, {kind = .Mark, text = ""}) }
		range := edit.selection(&t.mirror)
		value := edit.value(&t.mirror)
		selected := strings.clone(value[range.start:range.end], context.temp_allocator)
		// A marked replacement preserves the selection between both deletions;
		// a following commit replaces it, exactly like the original selection.
		wayland_text_enqueue(w, {kind = .Mark, text = selected, has_replacement = true,
			replacement = {max(0, range.start - int(t.before)), min(len(value), range.end + int(t.after))},
			selection = {0, len(selected)}})
		if !t.got_commit && !t.got_preedit { wayland_text_enqueue(w, {kind = .Unmark}) }
	}
	if t.got_commit { wayland_text_enqueue(w, {kind = .Commit, text = t.commit}) }
	if t.got_preedit {
		if len(t.preedit) > 0 {
			selection := t.selection
			if selection.start < 0 && selection.end < 0 { selection = {len(t.preedit), len(t.preedit)} }
			wayland_text_enqueue(w, {kind = .Mark, text = t.preedit, selection = selection})
		} else if t.mirror.composing { wayland_text_enqueue(w, {kind = .Cancel_Composition}) }
	}
	t.ime_change = true
	// Core publishes the resulting state after applying the operations.
}

@(private)
wayland_text_key :: proc(w: ^Wayland_Window, code: u32) {
	t := &w.text_input
	if t.client.target == 0 || w.xkb_state == nil { return }
	key, known := wayland_key(w, code)
	mods := w.keyboard.modifiers
	command: input.Text_Command
	matched := true
	if .Control in mods {
		#partial switch key {
		case .A: command = .Select_All
		case .C: command = .Copy
		case .X: command = .Cut
		case .V: command = .Paste
		case .Z: command = .Redo if .Shift in mods else .Undo
		case .Y: command = .Redo
		case .Left: command = .Word_Left
		case .Right: command = .Word_Right
		case .Backspace: command = .Delete_Word_Backward
		case .Delete: command = .Delete_Word_Forward
		case .Home: command = .Home
		case .End: command = .End
		case: matched = false
		}
	} else {
		#partial switch key {
		case .Left: command = .Left
		case .Right: command = .Right
		case .Home, .Up: command = .Home
		case .End, .Down: command = .End
		case .Backspace: command = .Backspace
		case .Delete: command = .Delete
		case .Enter, .KeypadEnter: command = .Submit
		case .Escape: command = .Cancel
		case: matched = false
		}
	}
	// IME-owned keys arrive through text-input. Ordinary wl_keyboard events
	// still need XKB translation even when the optional protocol is enabled.
	if t.mirror.composing { if known { t.handled += {key} }; return }
	if matched && known && .Super not_in mods && .Alt not_in mods {
		t.ime_change = false
		wayland_text_enqueue(w, {kind = .Command, command = command, extend = .Shift in mods})
		t.handled += {key}; return
	}
	if .Control in mods || .Super in mods || .Alt in mods { return }
	if t.compose_table == nil && w.xkb_context != nil {
		locale := os.get_env("LC_ALL", context.temp_allocator)
		if locale == "" { locale = os.get_env("LC_CTYPE", context.temp_allocator) }
		if locale == "" { locale = os.get_env("LANG", context.temp_allocator) }
		if locale == "" { locale = "C.UTF-8" }
		t.compose_table = xkb_compose_table_new_from_locale(w.xkb_context, strings.clone_to_cstring(locale, context.temp_allocator), 0)
		if t.compose_table != nil { t.compose = xkb_compose_state_new(t.compose_table, 0) }
	}
	buffer: [128]u8
	length: i32
	if t.compose != nil {
		xkb_compose_state_feed(t.compose, xkb_state_key_get_one_sym(w.xkb_state, code + 8))
		switch xkb_compose_state_get_status(t.compose) {
		case 1: if known { t.handled += {key} }; return // Composing a dead-key sequence.
		case 2: length = xkb_compose_state_get_utf8(t.compose, raw_data(buffer[:]), len(buffer)); xkb_compose_state_reset(t.compose)
		case 3: xkb_compose_state_reset(t.compose); return
		}
	}
	if length == 0 { length = xkb_state_key_get_utf8(w.xkb_state, code + 8, raw_data(buffer[:]), len(buffer)) }
	if length > 0 && length < len(buffer) && buffer[0] >= 0x20 && buffer[0] != 0x7f {
		t.ime_change = false
		wayland_text_enqueue(w, {kind = .Commit, text = string(buffer[:length])})
		if known { t.handled += {key} }
	}
}

text_listener := struct {
	enter: type_of(text_enter), leave: type_of(text_leave), preedit: type_of(text_preedit),
	commit: type_of(text_commit), delete: type_of(text_delete), done: type_of(text_done),
}{text_enter, text_leave, text_preedit, text_commit, text_delete, text_done}
