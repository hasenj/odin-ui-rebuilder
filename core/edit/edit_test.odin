package edit

import "core:testing"

@(test)
editing_pipeline :: proc(t: ^testing.T) {
	b: Buffer
	init(&b, "cafe\u0301 👩🏽‍💻 🇯🇵")
	defer destroy(&b)
	command(&b, .Backspace)
	testing.expect_value(t, value(&b), "cafe\u0301 👩🏽‍💻 ")
	command(&b, .Backspace); command(&b, .Backspace)
	testing.expect_value(t, value(&b), "cafe\u0301 ")
	command(&b, .Backspace); command(&b, .Backspace)
	testing.expect_value(t, value(&b), "caf")
	command(&b, .Undo)
	testing.expect_value(t, value(&b), "cafe\u0301")
	command(&b, .Redo)
	testing.expect_value(t, value(&b), "caf")
	// A composing sequence replaces a selection, commits once, and undoes
	// to the pre-composition document/selection in a single step.
	command(&b, .Select_All)
	apply(&b, {kind = .Mark, text = "に", selection = {3, 3}})
	apply(&b, {kind = .Mark, text = "日本", selection = {6, 6}})
	testing.expect_value(t, value(&b), "日本")
	testing.expect(t, b.composing && b.marked == (Range{0, 6}))
	apply(&b, {kind = .Commit, text = "日本語"})
	testing.expect_value(t, value(&b), "日本語")
	command(&b, .Undo)
	testing.expect_value(t, value(&b), "caf")
	testing.expect_value(t, selection(&b), Range{0, 3})
	apply(&b, {kind = .Mark, text = "仮", selection = {3, 3}})
	apply(&b, {kind = .Cancel_Composition})
	testing.expect_value(t, value(&b), "caf")
	testing.expect_value(t, selection(&b), Range{0, 3})
	apply(&b, {kind = .Commit, text = "abcdef"})
	apply(&b, {kind = .Commit, text = "x", replacement = {1, 5}, has_replacement = true})
	testing.expect_value(t, value(&b), "axf")
	// Ordered operations preserve text/key/text within a single UI interval.
	for op in ([]Operation{{kind = .Command, command = .Home}, {kind = .Commit, text = "A"},
		{kind = .Command, command = .Right}, {kind = .Commit, text = "B"}}) { apply(&b, op) }
	testing.expect_value(t, value(&b), "AaBxf")
	command(&b, .Select_All)
	apply(&b, {kind = .Commit, text = "line\nnext\tword"})
	testing.expect_value(t, value(&b), "line next word")
	command(&b, .Word_Left)
	testing.expect_value(t, b.cursor, 10)
	command(&b, .Delete_Word_Backward)
	testing.expect_value(t, value(&b), "line word")
	// History has a fixed entry limit and releases discarded snapshots.
	for _ in 0..<200 { apply(&b, {kind = .Commit, text = "!"}) }
	testing.expect_value(t, len(b.undo), 128)
}
