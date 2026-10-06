# Standard widgets

Created and maintained by Codex.

`widgets` imports `core`; core has no widget dependency. All geometry is in
logical window points. Widgets use **resolved rectangles** by default. Buttons
also accept explicit content or fixed sizing inside a local layout. Other widgets
still require rect cutting or resolved geometry.

```odin
import ui "path/to/core"
import w "path/to/widgets"

update :: proc() {
    // Load/cache a window-owned font once, then configure every window update.
    w.begin(font, scheme = w.light) // Omit scheme for dark.
    ui.open_rect(.Top, w.theme.height)
    if w.button("Save", .Primary) { save_document() }
    ui.close_rect()

    ui.open_rect(.Top, w.theme.height)
    if w.checkbox("Show hidden files", &show_hidden) { refresh_files() }
    ui.close_rect()
}
```

Widgets use the current remaining rect without cutting the caller's rect.
Menu items consume a row; `radio_group` divides its supplied area into rows.
Application values (selection, checked flags, numeric values, popup visibility)
remain caller-owned. Transient presses, drags, animation, and numeric edit drafts
use core's identity-owned state. `#caller_location` is forwarded through each
public wrapper. For reordered/dynamic content wrap calls in
`ui.open_identity(key = your_distinct_integer)` / `ui.close_identity()`; position
and text are not keys. Removing a widget removes its retained state.

## Color schemes and geometry

Call `begin` once at the start of **each window update** with that window's font
(or registered font-stack name). It resets the active colors and geometry and
checks that the previous update left no overlay scopes open:

```odin
w.begin(font, scheme = w.light) // w.dark remains the default.
// Optional: style = my_metrics, icons = my_icon_set.
```

`Color_Scheme` is a plain struct containing all widget paint colors. `w.dark` and
`w.light` are complete palettes; `w.colors` is the active mutable value. `Theme`
now holds only sizes/spacing (`w.default_theme` / active `w.theme`). Switching
colors does not change measurements, hit bounds, fonts, identities or editor state.
Existing callers reading `w.theme.text`, etc. should use `w.colors.text`; custom
old Themes should split colors into a Color_Scheme and metrics into a Theme.

Change the scheme directly at any point in the builder:

```odin
saved := w.colors
w.colors = w.dark
// Build a dark inspector inside the otherwise light window.
_ = w.panel_open("Properties")
w.label("Independent colors, shared geometry")
w.panel_close()
w.colors = saved
```

Assignments affect subsequent calls only. Surfaces and recorded local-layout
commands copy their paint colors, so restoring the scheme before `close_layout`
is safe. Deferred overlays use the scheme active when their builder runs: apply
an override again there if needed. No automatic scope stack or inheritance is
implied. Do not call `begin` again midway through a tree; it also starts the
widget frame's overlay bookkeeping. Font/icon resources stay window-owned.

Configuration is global to the currently running builder, which is serialized
across windows; it is not a process-wide preference or thread-safe worker API.
Each window must call `begin` with its chosen scheme on every update. Persist
the user's preference in application data, not in `w.colors`.

### Semantic color roles

The complete fields and palette values are in [colors.odin](colors.odin).
Colors are shared by meaning, not merely because they happen to have equal values:

| Roles | Used for |
| --- | --- |
| `background`, `surface`, `border`, `divider` | Window canvas, panels and separating rules. |
| `text`, `text_muted`, `text_disabled` | Shared content hierarchy and unavailable controls. |
| `control*` | Neutral controls, hover/press, borders and disabled fills. |
| `primary*`, `on_primary` | Primary actions and their state-specific fills/foreground. |
| `destructive*`, `on_destructive` | Destructive actions, independent of error indicators. |
| `focus`, `tab_indicator` | Keyboard focus and selected-tab underline, independently adjustable. |
| `selection`, `on_selection` | Selected list/menu/segment backgrounds and foregrounds. |
| `field`, `field_disabled`, `placeholder`, `text_selection`, `error` | Editor backgrounds, placeholders, selected text backdrop and validation. |
| `checked`, `on_checked` | Checked marks, radios and active switches. |
| `track`, `track_fill`, `thumb*` | Value tracks and movable thumbs; thumbs do not inherit text color. |
| `scrollbar*` | Scroll thumb and hover/drag feedback. |
| `badge_neutral*`, `badge_success*`, `badge_warning*`, `badge_error*` | Independent background/border/text triplets for status badges. |
| `overlay`, `overlay_border`, `modal_scrim`, `shadow_*` | Raised surfaces, modal dimming and ambient/contact shadows. |

Primary and destructive hover/pressed colors stay in their respective color
families. Scheme changes recolor current hover animations immediately; the
retained animation fraction continues, not an interpolation from the old palette.
To customize, copy a built-in scheme and override the desired fields. Selected
editor text keeps the normal text foreground, so choose `text_selection` with
that foreground in mind. The color schemes do not scan fonts or create native
platform widgets.

## Controls

- `button(label, kind, enabled, sizing, size, icon)` — Secondary, Primary, Destructive,
  Quiet. Default `.Fixed` uses the current rectangle; the label shrinks to fit
  down to half the theme font size, with any remaining overflow clipped.
  Inside `ui.open_layout`, opt into `.Content` for label size plus padding, or
  use `.Fixed` with an explicit positive `size`. Content sizing requires an
  active local layout. It never silently starts one. Fixed size is bounded by
  the enclosing area; outside a local layout an optional `size` also constrains
  the supplied rectangle. All modes share interaction, identities and styling.
- `icon_button(name, enabled)` is a convenience wrapper for an icon-only Quiet
  button using the configured set: Close, Up, Down, Left, Right, Plus, Minus,
  More, Check, Search. Quiet buttons paint their background only during hover/press.
- `checkbox(label, ^bool)` and `checkbox_state(label, ^Check_State)` — Off/On/Mixed.
- `radio(label, selected)` returns activation; `radio_group(items, ^index)` adds
  one Tab stop and arrow navigation to a static vertical group.
- `toggle(label, ^bool)` animates its thumb and track.
- `text_field(^ui.Text_Edit, placeholder, enabled, invalid)` returns core's edit
  result (changed/submitted/error). Initialize/destroy the caller-owned editor
  with `ui.init_text_edit` / `ui.destroy_text_edit`. This preserves core's IME,
  selection, clipboard and configured font fallback. It is single-line.
- `search_field(^ui.Text_Edit, placeholder)` places a search icon and clear button
  inside a shared field border. Clearing returns focus to the editor; filtering is
  application policy. Do not share one editor between independently editable fields.
- `number_input(^f64, low, high, step)` supports editing, plus/minus and Up/Down.
  The centered editor and inset-focus buttons share one border with dividers.
  Valid changes update the model; invalid drafts are marked and reverted on
  submit or focus loss. Limits must be finite. There is no locale number parser.
- `slider(^f32, low, high, step)` supports pointer dragging outside its bounds,
  arrow steps, Home/End and cancellation. Zero step uses a continuous pointer
  value and 1% keyboard increments.
- `progress(fraction)`, `badge(label, kind)`, `label`, `separator` paint only.
- `tabs(items, ^index, segmented)` uses a single Tab stop and Left/Right/Home/End.
- `list_item(label, selected, enabled)` provides activation and selection paint;
  applications own list data, virtualization, range selection and sorting.
- `scrollbar()` runs inside `ui.open_scroll`, before building children; it adjusts
  that scroll scope and paints a draggable track at the right edge. Reserve the
  rightmost 10 points for it so later child surfaces don't paint over the thumb.

Mouse buttons activate on release inside after press inside. Enter activates on
press; Space on release. Disabled controls never activate. Modifiers and text
adapter handled-key flags prevent ordinary button activation from text/IME
commands. All reads remain non-consuming; input is still accessible to callers.
Hover, pressed, focus and selected are separate states. Controls use the core's
previous-frame hit geometry, so newly appeared/repositioned controls settle on
the next frame. Focus rings use hollow GPU outlines.

## Containers and overlays

Icons are ordinary `ui.Icon_Glyph` values, independent of any particular set:

```odin
if w.button("Save", .Primary, icon = w.icon(.Check)) { save_document() }
if w.button("", icon = another_package.close) { close_panel() }
```

The default set is an original ten-glyph font, embedded by `icons/default`.
`w.begin` loads it once per window and retains its resolved glyphs. Applications
can pass a complete replacement as `w.begin(font, icons = my_icon_set)`, or
pass individual glyphs to buttons. Font handles/glyph values belong to the window
that loaded them; do not reuse them across windows. `theme.icon_size` controls the
ink's maximum extent, and `theme.gap` separates it from a nonempty label.
Fixed buttons keep the icon's size while text fits the remaining width. Content
buttons include icon, gap, text and padding in measurement. Icon-only buttons
have no label gap. See [the icon package](../icons/default/README.md) for sources
and the optional regeneration command.

```odin
ui.open_layout(.Left, {flow = .Row, gap = 8})
if w.button("Save", .Primary, sizing = .Content) { save_document() }
if w.button("Cancel", sizing = .Fixed, size = {100, 32}) { cancel() }
_, err := ui.close_layout()
```

The builder runs once. Layout measures and places recorded content, using the
previous frame's geometry for hover/focus/clicks as usual. A content button's
padding is `theme.padding` vertically and `1.5 * theme.padding` horizontally.
Cross-axis stretching follows the enclosing layout; fixed sizes take precedence.

- `disclosure_open(label, ^expanded)` returns true with its content scope open;
  pair it with `disclosure_close` only on true. `tree_open/close` and
  `accordion_open/close` are aliases. Supply the full expanded area; these do
  not measure children or impose a tree data model. Left/Right collapse/expand.
- `panel_open(title, closable)` always opens a content scope, returns a Close
  activation, and is always paired with `panel_close`. It is an in-window panel,
  not an OS window. The example Properties inspector is composed from controls.
- `menu_open(^visible, anchor, size)` / `menu_close()` create an anchored, shadowed,
  scrolling menu. `menu_item(label, shortcut, checked, enabled, destructive,
  dismiss)` and `menu_separator()` consume rows. Shortcuts are visual hints;
  applications bind shortcuts themselves. Default activation dismisses the menu
  chain. Up/Down/Home/End move among enabled items; Enter/Space activate.
- `submenu_open(label, ^visible, size)` consumes the parent row; on true, add
  children and pair with `submenu_close`. Click/Enter/Right opens; Left or Escape
  closes the submenu. Submenus currently open explicitly, not on hover delay.
- `context_menu_open(^visible, size)` attaches right-click opening to the current
  rect. On true pair with `context_menu_close` after declaring its items.
- `dropdown(items, ^selected)` combines a trigger and a scrolling selection menu.
  Its label and arrow form one button with a shared focus outline and Tab stop.
- `popover_open(^visible, anchor, size)` / `popover_close()` provide arbitrary
  content with outside-click and Escape dismissal.
- `dialog_open(title, ^visible, size, actions_height)` / `dialog_close()` add a
  centered modal barrier, title and Close button, with `theme.dialog_padding`
  around the interior (24 px by default). An optional positive `actions_height`
  reserves a bottom action area before laying out the clipped body. After the
  body, call `dialog_actions_open()` / `dialog_actions_close()` to build buttons
  beneath its divider; this scope stays anchored to the bottom even if the body
  is overfull. Without actions, leave `actions_height` at zero. Outside clicks
  don't dismiss dialogs. Escape and Close do.
- `tooltip(text, delay)` attaches to the current identity's hover; it doesn't
  intercept input or take focus.
- `show_toast(^Toast, duration)` then `toast(text, ^Toast, action)` provide a timed
  notification with Close and an optional action result. Text stays caller-owned.

Every successful menu/popover/dialog/context-menu open must be closed in the
same update. All descendants remain in the identity tree of their caller.
Popups flip/clamp to the current window, escape ancestor clipping, use layers,
block pointer fall-through, fence keyboard focus and restore it on removal.
Escape affects only the last/top overlay from the previous update. Outside-click
on a submenu dismisses its chain if outside every ancestor menu, or only the
submenu when inside its parent. Layer bands 100..410 are reserved for these
scopes; toasts use 450 and tooltips 500. Current maximum nesting is 32.
`size` includes popup padding; provide enough height for declared menu rows.
Long menus scroll and focused children are revealed by core.

## Gallery and checks

```sh
./scripts/build.sh demo16
./bin/demo16
./bin/demo16 --capture        # Dark reference captures
./bin/demo16 --capture-light  # Light reference captures
./scripts/check.sh
```

The gallery starts light and has a **Light theme** switch. **Mixed preview**
(visible at wider widths) paints the Properties inspector using the opposite
scheme. Both controls use ordinary widgets. The gallery adapts from three columns
to one at narrow widths. Capture writes
`bin/demo16-controls.png`, `-menu.png`, `-dialog.png`, `-popover.png`, and
`-compact.png`, `-tooltip.png`, and `-toast.png`. The widgets integration test drives synthetic input through the
actual builder and renderer: cancelled clicks, press/release, dragging outside,
text delivery, disabled controls, keyboard dropdown selection, tab navigation,
modal dismissal, radio navigation, numeric draft validation, scrollbar dragging,
key-based reorder/removal, nested Escape and outside dismissal
without click-through. Renderer readback tests check actual shadow/outline pixels. Scheme tests switch
colors while an editor retains focus and text, compare local-layout geometry,
and check GPU pixels for dark/light/custom schemes in one layout at 1x/2x.
Light captures have a `demo16-light` prefix; `-mixed` and `-switched` captures
exercise a subtree override and the live theme switch.

The design references are in `design/widgets/`. They are visual targets, not
promises of pixel-identical generated artwork. Icons use FreeType's antialiased
coverage through the shared glyph atlas; no staircase geometry or icon shaping.
Shadows and borders are implemented in both Metal and GLES; the new GLES path
still needs native execution on Linux (the development Mac lacks Linux STB libs).

On macOS, Odin `dev-2026-10-nightly:84bc3fc` currently asserts in the compiler
(`missing procedure objc_lookUpClass`) when compiling the widget test target.
Normal optimized demo builds/captures work. The scheme integration tests were
verified with `dev-2026-09-nightly:a2fb372`; the October compiler remains active.
