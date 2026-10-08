# Text input and single-line editing

Text input is separate from physical keyboard snapshots. Shared core implements
editing; macOS and Wayland provide native text-input and clipboard adapters.
The shared editor also accepts synthetic input for capture and testing.

## Build an editable field

```odin
// Application data. No editor object or editor initialization.
name := strings.clone("Initial text", app_allocator)
defer delete(name, app_allocator)

// Inside the UI builder:
ui.open_rect(.Top, 48, key = field_id)
{
    ui.paint(color = background, corners = 6)
    ui.pad2(6, 12)
    result := ui.edit_text(&name, "UI", size = 20, allocator = app_allocator)
    if result.changed { /* name now contains the committed edit */ }
    if result.submitted { /* Enter */ }
}
ui.close_rect()
```

`edit_text` accepts a `^string` or `^[dynamic]u8` (also spelled `[dynamic]byte`).
The optional result reports `changed`, `submitted`, `error`, `composing` and
`empty` (the displayed editor is empty, for placeholder painting). Ignore it
when no reaction is needed. `changed` means the committed model content changed
in this call, not merely that the selection or IME preedit changed.

The field's identity owns selection, undo/redo, caret geometry, horizontal
scrolling and composition. Its private child identity leaves the application's
own `ui.state` slot available. The binding never retains the model pointer:
moving application storage with the same value does not reset editing state.
Use stable item keys when declaring fields in a reorderable collection.

### Ownership and external updates

- A string must be empty or own its complete allocation from `allocator`, which
  defaults to the caller's `context.allocator`. On a committed change the field
  allocates a replacement and frees the old value through that allocator.
  Do not pass a nonempty literal, borrowed substring or temporary string as an
  owned model. The application releases the final string, using the same allocator.
- A dynamic byte array uses its own stored allocator and reuses capacity. A
  zero-initialized array needs no setup: its first edit adopts the supplied or
  active allocator. The application eventually calls `delete(buffer)`.
- Editor storage uses the window's persistent allocator independently of the
  model allocator. Removing the field releases editor state, but never releases
  or invalidates the application value. Reappearing fields start a new editing
  session; keep them declared if their selection/history must survive.
- External content changes are authoritative. They cancel composition, clear
  stale undo history and clamp selection to the replacement. Already queued
  text operations for that field are ignored for that synchronization call.
  Equal contents preserve state, even if the allocation/address changed.

IME preedit stays internal. Commit/unmark publishes the committed result;
cancelling composition leaves the model unchanged. Multiple edits in one call
publish the final committed value once. Disabled fields ignore input and cancel
preedit. The search field's clear button clears the model and cancels preedit.

Warm calls compare contents to detect external changes but do not copy or
allocate. The editor retains its working buffer separately from either model
representation. `edit_text_state` and `Text_Edit` remain low-level engine APIs
for custom controls such as the numeric input; ordinary text fields need neither.

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
order. Native command bindings use Command on macOS and Control on Wayland for
select all, copy/cut/paste and undo/redo. History retains at most 128 whole-buffer snapshots;
each commit is an undo step, while an entire IME composition is one step.
Typing coalescence, richer word-boundary rules and multiline editing are future
improvements. Pasted line breaks/tabs become spaces.

Geometry uses the same shaped advances as drawing. Ligatures divide their
advance among graphemes; OpenType ligature caret tables could improve precision.
Bidi boundary affinity is retained for visual/pointer movement; after an edit,
the following grapheme's leading edge is preferred. Pass either one font or a named `font_stack` to select an ordered fallback
list. Drawing, caret geometry and selection all use the same resolved faces.
If no face covers a character, its missing-glyph symbol (tofu) is rendered in
place; surrounding text and editing remain functional. Call `discover_fonts()` once to enable cached automatic fallback from installed
fonts; see [the text catalog API](TEXT.md#system-font-catalog).

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
core checks do not modify the clipboard. The optional Wayland native-input
check temporarily exchanges text and restores the previous text selection.

- `core/edit` tests: editing, graphemes, composition, cancellation, undo/redo.
- `core/text` tests: Latin/Arabic caret spans agree with shaped widths.
- Core capture checks: visual movement, selection collapse and no allocations
  during unchanged frames, with complete resource cleanup.
- `tests/text_input`: native range conversion, repeated preedit, commit ordering,
  focus-loss cancellation, native key interpretation/undo and window teardown.
- `demo15 --capture`: editor/selection/composition PNGs under `bin/`.
- `demo15`: live Latin, Arabic and Japanese fields for IME/clipboard verification.
  Its Japanese font uses Hiragino on macOS or the system Noto Sans CJK file on
  Arch Linux (`noto-fonts-cjk`); missing glyphs remain local if the font is absent.

## Wayland adapter and verification

Wayland uses XKB for layout-aware typing, Compose/dead keys and repeat, plus
text-input-v3 when available for preedit, committed text, surrounding deletion
and logical caret geometry. An enabled protocol does not suppress ordinary
keyboard text: compositor input-method grabs handle IME-owned keys. Focus and
identity changes prevent stale composition events from reaching another editor.

`ui.text_input_capabilities()` reports basic typing, composition-protocol and
clipboard availability for the current window. Composition protocol support
requires a separately installed and configured input method to show candidates;
basic XKB typing remains available without it. Clipboard access uses native
Wayland data-device transfers and requires a focused seat/window for selection
access. The backend does not require clipboard command-line utilities.

`platform` tests exercise real XKB state and the text-input callback pipeline.
The optional [native input check](../scripts/check-wayland-input.py) drives
Hyprland key events into main/panel windows and checks clipboard exchange with
another client. See [LINUX.md](../platform/LINUX.md) for commands, dependencies
and transfer limits. Live IME candidate placement needs manual verification;
callback tests alone do not establish that an installed IME works correctly.
