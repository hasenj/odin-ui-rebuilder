package input

// UTF-8 byte offsets, half-open. Native adapters translate UTF-16 indices
// at the boundary. NO_TEXT_RANGE denotes no marked range.
Text_Range :: struct {start, end: int}
NO_TEXT_RANGE :: Text_Range{-1, -1}
Text_Command :: enum {Left, Right, Word_Left, Word_Right, Home, End, Backspace, Delete, Delete_Word_Backward, Delete_Word_Forward, Select_All, Copy, Cut, Paste, Undo, Redo, Submit, Cancel}
Text_Operation_Kind :: enum {Commit, Mark, Unmark, Command, Cancel_Composition}
Text_Operation :: struct {
	target: u64, // Zero inherits Text_Input.target; native operations carry their owner.
	kind: Text_Operation_Kind,
	text: string,
	replacement: Text_Range,
	has_replacement: bool, // False replaces the current marked range or selection.
	selection: Text_Range, // Relative to inserted marked text.
	command: Text_Command,
	extend: bool,
}
Text_Input :: struct {
	target: u64,
	operations: []Text_Operation, // Ordered frame data; reads do not consume it.
	handled_keys: Keys, // Still present in raw keys; suppress duplicate UI actions.
}
// Core publishes this at frame end. Strings live through publication. Native
// adapters copy what they need; no callback into the UI builder is permitted.
Text_Client :: struct {
	target: u64, // Zero disables native text input.
	value: string,
	selection: Text_Range,
	marked: Text_Range,
	has_marked: bool,
	caret_position, caret_size: [2]f32, // Window content points, Y down.
}
