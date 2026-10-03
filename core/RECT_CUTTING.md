# Rect cutting

Every update starts with a root rect covering the window in logical points.
Geometry is available immediately; there is no layout tree or resolution pass.

```odin
update :: proc() {
    ui.pad(16)
    ui.open_rect(direction = .Top, size = 80)
    {
        ui.paint(color = ui.hsl(240, 50, 50), corners = 8)
        ui.pad2(8, 12)
        // Cut and paint more elements inside the header.
    }
    ui.close_rect()

    ui.open_rect(.Left, 200)
    {
        ui.paint(color = ui.hsl(220, 20, 20))
    }
    ui.close_rect()

    // The remainder is the main area.
    ui.paint(img = picture, corners = 8)
}
```

`open_rect` removes a strip from the current remaining space and enters it.
`.Top` and `.Bottom` take a height; `.Left` and `.Right` take a width.
`close_rect` returns to the already-reduced parent. Changes inside a child do
not affect its parent. Pair every open with a close, including zero-sized cuts.
The root cannot be closed, and all child scopes must close before update returns.
Braces are ordinary Odin variable scopes; the calls manage rect scopes. Each rect
scope also opens/closes a corresponding [identity node](IDENTITY.md). This does
not change the geometry calculations or introduce a layout resolution pass.

## Padding and queries

- `pad(all)` insets every edge.
- `pad2(vertical, horizontal)` follows CSS ordering.
- `pad4(top, right, bottom, left)` follows CSS ordering.
- `current_rect()` returns the remaining area as a value snapshot.
- `current_bounds()` returns the original area assigned to the current scope.
- Both snapshots are `Rect {position, size: [2]f32}` in window coordinates.

Cuts clamp to the available extent. Padding consumes left/top first, then
right/bottom, each clamped to what remains. Exhausted dimensions become zero;
positions remain inside the previous rect. Negative or nonfinite lengths are
programming errors. Padding never changes original bounds.

After an axis is exhausted, further cuts along that axis are empty and share
the same edge position. Empty surfaces do not render; `text()` also suppresses
glyph emission when either current dimension is zero. This is not clipping:
text in a nonempty rect can still extend beyond its bounds.

## Hover

`hovered()` tests the current remaining rect against the frame's pointer position.
Call it before padding/cutting to match a button's painted background:

```odin
color := ui.hsl(220, 25, 20)
if ui.hovered() { color = ui.hsl(220, 55, 45) }
ui.paint(color = color, corners = 12)
ui.pad(8)
```

`hovered(rect)` tests an explicit snapshot; `hovered(current_bounds())` uses the
whole scope even after padding or child cuts. Empty rects and pointers outside
the window content never hover. Top/left edges are included; bottom/right are
excluded so adjacent areas do not both match their shared edge.

This is a geometry query, without identity or retained state. Rounded paint
corners and overlapping surfaces do not affect it; overlapping rects can both
report hover. `examples/demo8` demonstrates three sidebar buttons changing color.

## Painting

`paint(color = ..., img = ..., corners = ...)` immediately appends a `Surface`
using the current remaining rect. It creates no layout element and consumes no
space. Calls use Odin named arguments; all arguments are optional.

Color defaults to opaque white, so `paint(img = picture)` preserves the image's
colors. An explicit color tints it. Images stretch to the rect, matching the
low-level renderer. Corner radius defaults to zero and applies only to the
emitted surface. The renderer limits it to fit that surface.

`hsl(hue, saturation, lightness, alpha = 1)` returns a `Color`. Hue is in degrees
and wraps; saturation/lightness are percentages clamped to 0–100. Alpha is 0–1.

Painting captures geometry at that moment. Paint before padding/cutting to make
a background; paint afterward to draw in the remaining space. Surfaces retain
declaration order, including those appended directly to `current_frame().surfaces`.
Rounded backgrounds do not clip later surfaces, and radii do not inherit through
cuts. Clipping is not implemented.

## Storage

Each geometry scope holds only its original bounds and remaining rect. A dynamic
stack keeps the active geometry scopes. The separate identity store retains
matching nodes across frames; it does not retain rect geometry. Padding and
closing take constant work; opening also performs identity hash lookups. Stack
storage is proportional to maximum nesting depth; surface storage is proportional
to emitted paint. Buffers retain capacity between frames and are freed when the
window closes.

The frame is implicit and valid only during the window's update callback, on
its main thread. `examples/demo4` demonstrates nested cuts, padding, HSL colors,
rounded paint, images, and resizing.

For localized content-sized rows/columns, see [LAYOUT.md](LAYOUT.md). A local
layout resolves before consuming its strip from the current remaining rect.
