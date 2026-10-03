# Clipping, scrolling, layers, hover and focus

These are UI building blocks, driven by the frame's input snapshot. No widget
callbacks or input consumption are required. Both native backends populate
pointer position, held buttons, wheel/trackpad movement, physical-key
transitions and modifiers. Capture or another host can supply the same data.

## Clipping and translated geometry

```odin
ui.open_clip() // Snapshot of current_rect(); an explicit Rect is also accepted.
ui.open_offset({0, -40})
{
    // Rect cuts, paint, text, images and direct surface appends are all clipped.
}
ui.close_rect() // Close the translated rect.
ui.close_clip()
```

`open_clip`/`close_clip` leave layout untouched. Nested rectangular clips
intersect. Empty intersections hide everything. Coordinates are logical points,
with inclusive top/left and exclusive bottom/right edges. Both GPU backends test
fragment centers against the same window-relative bounds; a clip scales with the
render target and does not alter a surface's UVs or glyph layout. Rounded masks
are not implemented. Surface corner radii still affect only that surface.

`open_offset(delta)` enters a translated copy of the current remaining rect.
`open_rect_at(Rect, key = ...)` enters any resolved window-relative rectangle
without consuming its parent. Both open identities and close with `close_rect`.
Existing clips stay fixed while the content geometry moves. Unlike clipping,
opening a rect does not automatically clip its children.

The framework stamps visual state onto newly emitted surface ranges at scope
boundaries, so each surface is processed once rather than once per ancestor.
This covers direct appends to `current_frame().surfaces` too. Append only: do not
clear, reorder or overwrite that array during an update. Explicit per-surface
clips intersect with the enclosing clip.

## Layers and overlays

```odin
ui.open_layer(10, escape_clip = true)
ui.open_rect_at(popup_bounds)
{
    ui.paint(color = popup_color)
    // Popup children retain their logical identity parent.
}
ui.close_rect()
ui.close_layer()
```

Z-index is absolute and signed; the default is zero. Higher layers draw later.
Declaration order is preserved within a layer, including translucent surfaces.
Only the small set of layer numbers is ordered; surface runs are copied into
buckets without sorting individual glyphs. Buffers retain their capacity.

Enter a layer before opening its interactive rects: each rect records the layer
and clip present when it opens. `escape_clip` removes ancestor clipping for that
layer scope; clips opened inside it still work. All rect, clip, scroll and layer
scopes must be balanced. Close nested clips before closing their layer.

## Resolved hover

`hovered()` checks the current identity. `hovered(id)` checks another identity;
`direct_hover()` returns the directly hit identity, or zero.

At update start, the current pointer is tested against the previous frame's
rectangles and clips. Highest layer wins, then deepest identity, then latest
declaration. Every opened rect participates by default. `set_hit_test(false)`
disables the current rect's direct participation while leaving its descendants
independent. Use this for decorative overlays that should let the pointer pass.

Ancestors are secondarily hovered only when their own recorded bounds and clip
contain the pointer. Logical identity scopes with no rectangle inherit their
child's hover. Original assigned bounds are used, not the remainder after
padding/cuts. First appearance has no previous geometry and cannot be hovered
until the next update. Removal/repositioning likewise takes effect in the next
hit-test pass. Newly opened overlays therefore require a settling update.

`hovered(Rect)` is deliberately a raw geometry query: it checks current pointer
position and the active clip but ignores identity/layer occlusion. This remains
available for components that need it.

## Scroll regions

```odin
ui.open_scroll({ui.current_rect().size.x, content_height}, key = list_id)
{
    offset := ui.current_scroll().offset
    // Optional: ui.scroll_to({0, desired_y}) before declaring the children.
    // Ordinary cuts now operate on the full, translated content canvas.
}
ui.close_scroll()
```

The enclosing remaining rect is the fixed viewport. Content extent is explicit;
each axis is at least the viewport extent. Offsets are retained by the scroll
scope's identity and clamped to `[0, content_size - viewport_size]`, including
after resizing or shrinking content. Disappearing identities release their state.
`current_scroll()` returns a value snapshot. `current_bounds()` remains the
viewport while `current_rect()` is the translated content/remainder.

`input.scroll_delta` is per-update movement in logical points, positive towards
the content bottom/right. The deepest visible scroll ancestor of the direct hit
moves first. Any movement it cannot perform passes to outer scroll ancestors;
axes are handled independently. Raw input is never consumed or modified.
Invisible/occluded regions cannot receive wheel movement. Programmatic
`scroll_to` updates geometry immediately and should be called before children.

A newly focused child is revealed by scrolling its ancestors, inner to outer.
Manual scrolling can hide an unchanged focus owner without snapping back. There
is no overscroll, framework-generated inertia, or built-in scrollbar yet. Native
trackpad momentum arrives as ordinary scroll deltas. macOS precise deltas stay
in logical points; coarse wheel steps use 40 points per line. Wayland axis values
already use logical surface coordinates. Both hosts accumulate movement between
frames and reset their pending delta after supplying each input snapshot.

## Focus and keyboard data

Call `focusable()` on a rect to participate in click/Tab focus. Passing false
keeps it drawable/hoverable but excludes it from focus traversal. `focused()`
includes descendant focus; `direct_focus()` is the exact owner. The overload
`focused(id)` checks an explicit identity. `request_focus()` or
`request_focus(id)` requests focus; `clear_focus()` clears it. A focus owner must
be a currently declared focusable rect. Register rect properties while that
rect's identity is current, not inside a separate logical identity scope.

Click focuses the nearest focusable ancestor of the directly hovered rect.
Clicking non-focusable background clears focus. Mouse press can be supplied
explicitly or inferred from changes in held buttons. This uses prior geometry,
just like hover. Holding a button does not repeatedly move focus.

Tab advances through focusable rects in declaration order and wraps. Shift-Tab
reverses. Control/Alt/Super-Tab is left to application policy. Disabled or zero-sized entries are skipped. Focus is removed when its
owner disappears or becomes non-focusable. Components may read any input field
regardless of focus; checking `focused()` is a voluntary component policy.

`focus_fence()` on a rect confines focus to its identity subtree while present.
The highest-layer/deepest/latest fence wins. Nested fences remember prior focus,
and closing them restores it if the owner remains eligible. If restoration is
impossible, an enclosing fence chooses its first eligible descendant; otherwise
focus becomes empty. A fence with no focusable descendants keeps focus empty.
A keyboard fence alone does not block pointer hits: a modal normally also uses
a full-window rect on its layer as a hit barrier (see demo10).

`keys_down`, `keys_pressed`, `keys_released`, `modifiers`, `mouse_pressed`,
`mouse_released` and `scroll_delta` are data supplied by a host. Transition sets
and scroll deltas must be cleared/replaced every update. The builder never
consumes them. `Key` names physical keyboard positions using US legends:
letters, top-row digits, punctuation, navigation, F1–F24, keypad keys, modifier
sides, lock keys, and selected international/system keys. `Keys` uses a 128-bit
set, so existing `.A in input.keys_down` / `keys_pressed` / `keys_released`
checks need no lookup or allocation. Shift+A is `.A` plus Shift; a changed
keyboard layout does not rename the position. This intentionally replaces the
earlier Wayland keysym mapping with physical evdev codes. XKB still supplies
configured modifiers, lock state and repeat policy.

Top-row `.Digit1` and `.Keypad1` are independent, as are `.Enter` and
`.KeypadEnter`; Num Lock does not change keypad identity. Modifier sides are
keys (`.LeftShift`, `.RightShift`, etc.), while `modifiers` holds the aggregate
Shift/Control/Alt/Super flags. `locks` holds Caps/Num/Scroll toggle state separately
from key-down state. On macOS, Caps Lock changes produce a press/release tap
because AppKit does not provide a reliable physical Caps Lock key-up sequence.
Not every named key exists or is delivered on every OS: macOS's normal keycode
path covers F1–F20, and OS-reserved shortcuts/media keys may be intercepted.
Character translation, dead keys, text entry and IME remain separate future work.

Window deactivation (macOS) or keyboard leave/device loss (Wayland) clears held keys,
cancels pending presses and stops repeat. Logical UI focus is remembered.
Text/IME input and on-demand frame scheduling remain deferred.

Native hosts set `has_key_press_modifiers` and populate
`key_press_modifiers[key]` with modifiers at the last press of that key in the
snapshot. Current held modifiers remain in `modifiers`. This lets a quick
Shift-Tab go backward even if Shift was released before the frame. Synthetic
hosts may leave the flag false; focus traversal then uses `modifiers` as before.
Repeated key-downs produce per-frame presses; transition sets coalesce multiple
presses of the same key between updates into one. macOS uses native key repeat;
Wayland uses the compositor's repeat rate/delay, without replaying missed repeats
after a stall. Key repeat does not arise merely from `keys_down` being set.

Demo11 is a keyboard inspector: it shows currently held keys, remembers the last
press/release sets, flashes their tiles, and displays aggregate modifiers and
locks. Run `./scripts/build.sh demo11` and `./bin/demo11`. Its `--capture` option
saves deterministic held/released examples to `bin/demo11-*.png`.

## Evidence and example

```sh
./scripts/build.sh demo10
./bin/demo10 --capture
```

This runs assertions and produces `bin/demo10-*.png` for ordinary focus, scrolling,
focus reveal, opening a modal by clicking, Tab inside the modal, closing with
either button, focus restoration, and resizing. It also checks cancelled clicks
and the modal's pointer/scroll barrier.
Running demo10 without the flag opens the sample window. Click **Open modal** in
the header, then **Continue** or **Cancel** to close it. Focus returns to the
opener. The sample activates buttons on release inside after a press inside;
dragging off before release cancels activation. Pointer hover/click focus and
wheel/trackpad scrolling work with native input. Tab and Shift-Tab cycle focus,
wrap inside the modal, and reveal focused items in the scroll region.

`./scripts/check.sh` tests the core and real Metal renderer, builds all examples
with speed optimizations, then runs the capture scenarios on macOS. Core tests
cover nested scroll chaining, resize/content clamping, clipped/occluded hover,
layer order, click/Tab focus, fences, cleanup, and allocation-free warmed frames.
Metal readback tests cover rectangular clip edges at 1x and 2x. GLES has the same
shader/attribute changes and Linux ARM64 compile coverage; actual Wayland/GLES
execution still needs the Linux host.

`./scripts/check-macos-input.sh` sends real precise and coarse NSEvents to the
production Metal view and verifies both axes, accumulation, next-frame delivery,
and reset on idle frames. It also sends native key events through NSWindow to
verify Tab/repeat, quick Shift-Tab, disabled entries, modified-Tab exclusion,
modal wrapping/restoration and reset when the window loses key status. Extended
key checks cover simultaneous holds, physical identity independent of event
characters, keypad distinction, both Shift keys, lock toggles and bits above 64.
The main-thread test explicitly drives draws so it finishes even when display
refresh callbacks stop; it does not require Accessibility permission. Linux
tests exercise pointer delivery, physical evdev keys and real XKB modifiers,
including quick Shift-Tab, repeat, keypad identity across Num Lock and leave reset.

### Native mouse transitions and cancellation

macOS accumulates mouse presses/releases between snapshots. A quick tap can set
both flags in one frame while held state is empty. Multiple transitions coalesce
into sets; their counts/order and individual coordinates are not retained.
Position is the latest sampled pointer position, including outside during a drag.
Focus loss clears held/pending presses, reports releases, and sets
`input.mouse_cancelled` for one update. End drags and discard pending click
activation on cancellation. Input reads remain non-consuming. Wayland currently
retains its prior held-state behavior pending its native implementation update.
