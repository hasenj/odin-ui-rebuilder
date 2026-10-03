# Text input and single-line editing

Text input is separate from physical keyboard snapshots. Shared core implements
editing; macOS implements the native input-method and clipboard adapter. Wayland
native text input and clipboard are intentionally deferred to its host agent.
The shared editor can already be driven using synthetic input on either host.

## Build an editable field

```odin
Field :: struct {editor: ui.Text_Edit}
init_field :: proc(field: ^Field) {
    ui.init_text_edit(&field.editor, "Initial text")
}
destroy_field :: proc(field: ^Field) {
    ui.destroy_text_edit(&field.editor)
}

ui.open_rect(.Top, 48, key = field_id)
{
    field := ui.state(Field, init_field, destroy_field)
    ui.paint(color = background, corners = 6)
    ui.pad2(6, 12)
    result := ui.edit_text(&field.editor, "UI", size = 20)
    if result.changed { /* read ui.text_edit_value(&field.editor) */ }
    if result.submitted { /* Enter */ }
}
ui.close_rect()
```

The caller owns appearance, layout and the buffer's lifetime. `Text_Edit` can
instead live in application data when it must survive UI disappearance. Destroy
it with `destroy_text_edit`. Do not reuse one editor instance for two fields or
windows simultaneously. The value returned by `text_edit_value` borrows its
buffer until the next edit/destruction. Programmatic edits go through
`core/edit` operations, which advance the revision used by geometry caching.

`edit_text` registers focus, handles input for its identity, paints text,
selection and caret, clips to its resolved rect, and scrolls horizontally to
reveal the caret. It does not paint a background or consume layout space. Use
it in resolved rect cutting, outside an open local-layout recording scope.
Pointer selection continues while dragging outside; focus-loss cancellation
ends dragging. Tab/Shift-Tab use normal framework focus traversal. Enter reports
`submitted`; Escape cancels an in-progress composition.

Arrow movement is visual left/right. Shift extends a logical selection;
selecting mixed-direction text may paint multiple disjoint visual spans.
Backspace/Delete operate on logical graphemes, including combining accents,
emoji modifiers, ZWJ sequences and flag pairs. Home/End select the logical line
endpoints. Word commands currently use whitespace-delimited words and logical
order. Native command bindings include the macOS Command shortcuts for select
all, copy/cut/paste, undo/redo. History retains at most 128 whole-buffer snapshots;
each commit is an undo step, while an entire IME composition is one step.
Typing coalescence, richer word-boundary rules and multiline editing are future
improvements. Pasted line breaks/tabs become spaces.

Geometry uses the same shaped advances as drawing. Ligatures divide their
advance among graphemes; OpenType ligature caret tables could improve precision.
Bidi boundary affinity is retained for visual/pointer movement; after an edit,
the following grapheme's leading edge is preferred. Pass either one font or a named `font_stack` to select an ordered fallback
list. Drawing, caret geometry and selection all use the same resolved faces.
If no face covers a character, its missing-glyph symbol (tofu) is rendered in
place; surrounding text and editing remain functional. System-font discovery
and automatic fallback outside the explicit stack remain future work.

For a custom editor, use `text_caret_spans` to obtain caller-owned grapheme
geometry and `text_hit_test` to map an X coordinate to a byte offset and visual
edge. Combine the spans with a logical selection range to paint its geometry.
The `core/edit` buffer/operations and `request_text_input` work independently of
`edit_text`; its provided builder is optional.

## Shared data contract for native adapters

`core/input/text.odin` defines:

- `Text_Client`: core's focused target, UTF-8 text, selection, optional marked
  range, and candidate/caret bounds in window content points (Y down).
- `Text_Input`: a borrowed per-frame list of `Text_Operation` values. These are
  readable data, not dispatched callbacks or an exclusive consumption queue.
- `Text_Operation`: Commit, Mark, Unmark, Cancel_Composition or a text command.
  Each operation has a target; zero inherits the snapshot target for convenient
  synthetic input. Target IDs pack the identity generation and slot, and remain
  local to their window.

All shared ranges are half-open UTF-8 **byte** ranges. `has_replacement = false`
means replace the marked range if composing, otherwise the selection. Mark's
selection is relative to its inserted text. Multiple operations between updates
retain ordering: type/move/type and successive IME changes cannot collapse into
one unordered key snapshot. Raw keys remain readable. `handled_keys` marks keys
interpreted by native text input, preventing duplicate focus traversal (notably
Tab used by an input method).

`request_text_input` publishes a client for the current directly focused
identity. Call each frame after editing and positioning the caret. Omission
turns the client off. The final focus owner determines the published target.
Input already delivered to the old target is applied to that target, even when
a click moves focus in the same frame; it must never leak into the new field.

`platform.text_input_update(renderer, client)` is called after the builder.
The native adapter copies required data, receives native callbacks between
updates, and exposes owned operation strings until the next input snapshot.
No native callback invokes the UI builder. Synthetic hosts can supply the same
operation list directly. The pure `core/edit` package handles text mutation,
selection, composition and history without a renderer, platform or UI context.

## macOS adapter and verification

The Metal view implements Apple's [NSTextInputClient protocol](https://developer.apple.com/documentation/appkit/nstextinputclient).
It interprets native key events, translates UTF-16 ranges at the boundary, accepts
NSString or NSAttributedString input, supplies surrounding text and selection,
and converts caret bounds to native screen coordinates for candidate placement.
A native mirror answers synchronous queries between UI updates; core owns the
actual editable buffer. Snapshot publication must not overwrite native operations
that arrived during the builder. Losing native keyboard focus cancels marked
text; moving UI focus commits the currently visible marked text into the old
field and disables its native composition session.

Live Japanese composition, candidate placement, commit and general editing
were confirmed by the user on macOS. Candidate geometry is caret-based in this iteration. Fine-grained native
character-at-point/range geometry, dictation-specific behavior and selective
panel keyboard focus remain follow-ups. Actual input-method behavior still
requires a human check; direct protocol callbacks alone do not verify a live
Japanese candidate window.

`clipboard_read` returns an owned string and success flag (delete the string);
`clipboard_write` returns success. Unsupported backends report false. Automated
checks do not overwrite the user's clipboard.

- `core/edit` tests: editing, graphemes, composition, cancellation, undo/redo.
- `core/text` tests: Latin/Arabic caret spans agree with shaped widths.
- Core capture checks: visual movement, selection collapse and no allocations
  during unchanged frames, with complete resource cleanup.
- `tests/text_input`: native range conversion, repeated preedit, commit ordering,
  focus-loss cancellation, native key interpretation/undo and window teardown.
- `demo15 --capture`: editor/selection/composition PNGs under `bin/`.
- `demo15`: live Latin, Arabic and Japanese fields for IME/clipboard verification.
  Its Japanese font is loaded from macOS's Hiragino font file, not embedded.
