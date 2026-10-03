# Local content-sized layout

Rect cutting still handles resolved regions. Inside one of those regions,
`open_layout` records a small layout tree; `close_layout` measures and positions
it, consumes a top/bottom strip, and emits its surfaces. Application code runs
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

## Sizing rules

- Flow is `.Column` by default, or `.Row`. `gap` separates immediate children.
- `padding = {vertical, horizontal}` applies inside the box, around its children.
  Painting covers the whole box, including padding.
- Width defaults to content size. `layout_fixed(n)` preserves an explicit width;
  `layout_fill(weight)` receives remaining width. Fill weights must be positive.
- A row reserves fixed widths and gaps first. Content children keep their natural
  widths when space permits, or share a shortage in proportion to their natural
  widths. Fill children divide any surplus by weight. Fixed children, padding,
  and gaps may overflow a very narrow allocation.
- A column constrains content children to its inner width. Fill children take
  that width; fixed children retain their explicit width.
- Height defaults to the extent of the children after text wrapping, plus
  padding/gaps. `height = layout_fixed(n)` overrides it. Height fill is unsupported.
- `align = .Start`, `.Center`, or `.End` positions children on the cross axis:
  vertically in a row, horizontally in a column. It does not stretch children.
- A content-width box cannot have a direct fill-width child. Give that parent a
  fixed or fill width to remove the circular sizing dependency.

The root consumes a `.Top` or `.Bottom` strip from the current resolved rect.
Its width is always the available width; leave the root style's width unset.
Its height is clamped to the remaining height, matching ordinary rect cutting.
The returned `Rect` describes that consumed strip. There is no automatic clip:
fixed content, unbreakable words or descendants of a height-constrained box may
extend outside it. Open a clip around the layout when that is undesirable.

There is no row wrapping, flex-basis, CSS shrink/min/max machinery, baseline
alignment, height fill, or left/right content-width root in this first version.
Text wrapping retains the existing text engine's rules, including unbroken long
words and explicit newlines.

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

Resolution visits those arrays for intrinsic measurement, width allocation,
width-dependent text measurement and height propagation, then placement. Finally
it writes hit bounds and emits surfaces in command order before ordinary cutting
resumes. Existing paragraph/shape/glyph caches are reused. Each tree pass is
linear in the number of nodes; text processing has its own cache-dependent cost.

## Example and evidence

```sh
./scripts/build.sh app13
./bin/app13
./bin/app13 --capture
```

App13 has content-sized buttons with hover fades and focus, click-to-reorder
behavior, and a card combining a fixed icon, wrapped text, and fill-width cells.
The content height moves subsequent sections without caller premeasurement.

Core integration checks verify exact resolved geometry, inherited clipping,
previous-frame hover/click focus, one execution per update, state through keyed
reordering, cleanup, bottom cuts, exhausted space, and warmed buffer reuse.
Metal capture checks compare wrapped/nested heights against the text engine at
1x/2x, validate temporary-string ownership and deferred errors, and save app13 at
wide/narrow sizes. Wayland runtime verification remains a Linux-host task.
