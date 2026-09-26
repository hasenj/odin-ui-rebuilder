# Layout foundation

`core/layout` computes geometry without rendering, input, or platform dependencies.
The UI package in `core` uses it to place `Container` backgrounds, emitted as
rendering `Surface` primitives. See `examples/app4` for a complete sample.

## Usage

The update callback takes no arguments. The current frame is implicit;
`ui.current_frame()` exposes the window size, time, input, and low-level surfaces.
Containers use explicit opening and closing, with ordinary Odin scopes between:

```odin
ui.container_open({layout = .Row, padding = ui.insets(12), gap = 8,
    background = {0.1, 0.1, 0.1, 1}})
{
    ui.container_open({width = ui.fixed(80), height = ui.fixed(40),
        background = {1, 0.5, 0, 1}})
    ui.container_close()
    ui.container_open({width = ui.fixed(60), height = ui.fixed(30),
        background = {0, 0.5, 1, 1}})
    ui.container_close()
}
ui.container_close()
```

Braces provide variable scope; opening and closing calls define the tree. All
containers must close before update returns. Layout resolves afterward.

## Sizing rules

- Default direction is column. Default width and height fit content independently.
- A row sums child widths and takes the maximum child height. A column does the
  reverse. Padding adds to both dimensions; gaps appear only between children.
- Fixed dimensions describe the outer box, including padding. Children may
  overflow a fixed parent; there is no automatic shrink or clipping.
- Empty fit containers measure to their padding, or zero with no padding.
- Children start at the parent's top-left padding edge. All units are logical
  points. Padding, gaps, and fixed dimensions must be finite and nonnegative.
- An implicit root has the viewport size and arranges top-level children vertically.

Grow/fill, wrapping, alignment, stable identities, attribute mutation, and input
queries are left for later stages. Internal node indices are frame-local and
must not become stable application identities.

## Storage and passes

Opening a container appends it in preorder. Topology is a contiguous array of
parent indices and direct child counts. Attributes, resolved sizes, resolved
positions, and scratch cursors occupy separate parallel arrays. There are no
child-pointer lists and no recursive layout traversal. Appending can relocate
arrays, so construction retains indices rather than pointers into them.

1. **Measure:** scan backward. Each completed child contributes its size to its
   parent's accumulator. Finalize a node with padding, gaps, and fixed overrides.
2. **Place:** scan forward. The parent's position is already known. A per-parent
   cursor places each direct child and advances by its size and the gap.

Both passes are O(n), with O(n) retained storage. Reset clears array lengths and
reuses capacity; allocations occur when capacity must grow. Resolve runs exactly
once per build. A frame integration test checks that rebuilding a warmed scene
does not allocate.

Painting data stays outside the geometry engine. Container backgrounds reserve
surfaces during construction; after layout, the UI fills in their positions and
sizes. This preserves declaration order when mixing containers and manually
appended surfaces. Transparent containers still participate in layout without
emitting a background surface.
