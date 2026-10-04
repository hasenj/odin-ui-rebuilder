# Local content-sized layout

Rect cutting still handles resolved regions. Inside one of those regions,
`open_layout` records a small layout tree; `close_layout` measures and positions
it, consumes a strip in the requested direction, and emits its surfaces. Application code runs
once, including input reactions and retained animation. The layout passes only
process recorded data.

```odin
ui.open_layout(.Top, {flow = .Row, gap = 8, padding = {8, 12}})
{
    for action in actions {
        ui.open_box({padding = {8, 12}}, key = action.id)
        {
            ui.focusable()
            color := normal_color
            if ui.hovered() { color = hover_color }
            ui.paint(color = color, corners = 6)
            ui.text_item(action.label, "UI", 16)
        }
        ui.close_box()
    }
}
area, err := ui.close_layout()
assert(err == .None)
// current_rect() now describes the remainder below the resolved strip.
```

`paint` records a surface for the current box; it contributes no size. Images
use the existing `paint(img = ...)` API inside a box with explicit dimensions.
`text_item` creates a content-sized leaf, wraps to its assigned width, and records
its draw operation. It accepts font name/handle, size, color, weight, direction,
and language. It copies text/language bytes into reusable local storage, so a
caller may immediately reuse its formatting buffer. Deferred text errors are
returned by `close_layout`; other successfully recorded content can still paint.

`stroke` records an outline against the current box as well; it does not affect
measurement. `layout_active()` lets compound builders choose between recorded
boxes and resolved rects without exposing the layout store.

For fixed label areas, `text_item` accepts `style` with explicit width/height,
`fit = true`, and `align` / `valign`. Fitted text stays on one line and shrinks
down to `min_scale` (0.5 by default), then clips remaining overflow to its leaf.
It is measured using the same constraints as other leaves, with no builder
replay. Put padding on the enclosing box; text leaves have no padding. Ordinary
`text_item` calls retain their existing wrapping and content-sizing behavior.

`icon_item(glyph, size, color)` adds a square icon leaf. `text_item` can also
accept `icon`, `icon_size`, and `icon_gap` for a combined label: its intrinsic
width includes the icon and optional gap, and fitted text uses only the remaining
width. An icon-only label has no gap. The same glyph primitive can be drawn in
resolved geometry with `draw_icon`, or combined with fitted text using `draw_label`.

## Sizing rules

Every root inherits maximum width **and** height from the current remaining rect.
It resolves to its content size within those bounds, rather than filling them.
Fixed sizes are also capped by the available bounds.

- Flow is `.Column` by default, or `.Row`. `gap` separates immediate children.
- `padding = {vertical, horizontal}` applies inside the box, around its children.
  Painting covers the whole box, including padding.
- Width and height default to content size. Use `layout_fixed(n)` to request an
  explicit size. There is no `Fill` size mode, growth weight, or flex shrink.
- A row adds child widths and gaps; a column adds child heights and gaps. Spare
  main-axis space stays unused. Children are each constrained by the parent's
  inner bounds, not assigned competing shares of its main-axis space.
- If siblings together exceed the main-axis extent, they overflow in declaration
  order. They are not proportionally shrunk or automatically wrapped onto a new
  row/column. Use clipping/scrolling or separate cut regions to handle overflow.
- Wrapped text is measured after width constraints and horizontal stretching
  resolve. Its height sizes its ancestors, subject to their height limits.
- `stretch = true` on a parent stretches its content-sized children across its
  resolved inner cross axis: width in a column, height in a row. A child's fixed
  cross size takes precedence. Stretch does not make the parent fill spare space.
- `align = .Start`, `.Center`, or `.End` positions children on the cross axis.
  Alignment matters for children that do not stretch (or have a fixed cross size).

For a menu, the widest natural entry plus menu padding determines the menu width,
up to the enclosing width limit. `stretch = true` then gives the other entries
that same inner width. Their painted backgrounds and hit bounds stretch together;
their content heights remain independent.

```odin
ui.open_layout(.Left, {gap = 4, padding = {8, 8}, stretch = true})
ui.paint(color = menu_background, corners = 8)
for item in items {
    ui.open_box({padding = {8, 12}}, key = item.id)
    ui.focusable()
    ui.paint(color = hovered_color if ui.hovered() else normal_color)
    ui.text_item(item.label, "UI", 16)
    ui.close_box()
}
menu_bounds, err := ui.close_layout()
```

Roots support `.Top`, `.Bottom`, `.Left`, and `.Right`. `close_layout` returns the
resolved **content bounds**, anchored to the requested edge and the start of the
other axis. It removes a full strip along the cut axis from the parent: top/bottom
consume resolved height; left/right consume resolved width. A left-cut menu can
therefore leave empty space below itself while reserving its column. Rect cutting
can place independent layout groups at the left and right ends of a toolbar.

There is no automatic clipping. Although resolved sizes are constrained, sibling
placement or glyphs for unbreakable words can extend outside their bounds. Open a
clip around the layout when overflow should be hidden. Text wrapping retains the
existing text engine's rules, including explicit newlines and unbroken long words.
There is no baseline alignment, row wrapping, or CSS flex allocation machinery.

## Identity, input, and retained state

Every root, box and text item immediately enters the existing identity tree.
Roots and boxes support caller-location keys or explicit integer keys, including
distinct integer types. Wrappers should forward `loc`; keyed repeated components
retain identities when reordered. Text items use caller location and occurrence.
Logical `open_identity` scopes work inside boxes too.

`hovered`, `focused`, `focusable`, `request_focus`, `focus_fence`, `set_hit_test`,
raw input, and identity-based animation work during declaration. Hit entries are
registered in declaration order and filled with final bounds after resolution.
At the next update, fresh input is resolved against those previous-frame bounds,
just as with rect cutting. A new/moved element does not retroactively receive
current-frame input based on its newly resolved position.

Layout adds no second state system: existing retained animation and scroll state,
and future general component state, continue to use the identity tree. Temporary
layout node indices are private, valid only during the local resolution.

## Resolved versus unresolved scopes

Use `open_box`/`close_box` to nest within one local layout. `current_rect`,
`current_bounds`, `pad`, ordinary rect cuts, offsets and scroll scopes require
resolved geometry and are rejected while layout is open. Existing `text` and
`draw_text_layout` also require a resolved rect; use `text_item` here.
Width-independent text measurement remains available when explicitly needed.

Clip and layer scopes must enclose the whole local layout. Changing them inside
an unresolved scope is currently rejected. All deferred surfaces and hits inherit
the enclosing clip/layer. The local layout can live inside an existing scroll
canvas or overlay. Direct appends to `current_frame().surfaces` inside unresolved
layout are unsupported and checked when the root closes.

These boundaries are deliberate: no geometry query quietly returns stale bounds,
and no callback is rerun to obtain a different result in another layout pass.

## Storage and passes

Declaration appends a preorder node array, parallel style/measurement/bounds
arrays, ordered paint/text commands, and copied string bytes. Parent indices and
subtree-end indices replace child pointers. Capacity is retained across roots
and frames; storage is released with the owning window/capture session.

Resolution visits those arrays for intrinsic measurement, width constraints and
horizontal stretch, width-dependent text measurement and height propagation,
then placement and vertical stretch. Finally
it writes hit bounds and emits surfaces in command order before ordinary cutting
resumes. Existing paragraph/shape/glyph caches are reused. Each tree pass is
linear in the number of nodes; text processing has its own cache-dependent cost.

## Example and evidence

```sh
./scripts/build.sh demo13
./bin/demo13
./bin/demo13 --capture
```

Demo13 demonstrates a menu sized by its widest entry, equal-width stretched
backgrounds and hit regions, hover fades, focus, selection and keyed reordering.
Independent left/right toolbar groups are placed with cuts. The explanation in
the remaining region wraps and sizes itself without caller premeasurement.

Core integration checks verify content-derived bounds, both stretch axes, fixed
cross-size precedence, width/height limits, no main-axis growth or proportional
shrink, inherited clipping, previous-frame hover/click focus, one execution per
update, state through reordering, cleanup, directional cuts, exhausted space,
and warmed buffer reuse. Metal captures compare nested wrapped heights with the
text engine at 1x/2x, validate temporary-string ownership and deferred errors,
and exercise clicks in the stretched part of a menu row. Wayland runtime
verification remains a Linux-host task.
