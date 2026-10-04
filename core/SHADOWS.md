# Shadows and outlines

Created and maintained by Codex.

```odin
ui.open_rect_at(panel_bounds)
ui.shadow(color = {0, 0, 0, 0.45}, offset = {0, 5}, blur = 9, corners = 4)
ui.paint(color = panel_color, corners = 4)
ui.stroke(border_color, width = 1, corners = 4)
// Contents...
ui.close_rect()
```

`shadow` emits a separate surface before the casting surface. It requires a
resolved rectangle, adds no identity/hit target and changes no layout geometry.
`blur` is Gaussian **standard deviation**, in logical points (not CSS blur-radius).
The GPU quad extends three standard deviations beyond the spread bounds.
`spread` expands/contracts the rectangle and its corner radius before blurring.
Zero blur emits a hard-edged shape. Offset may be signed. Negative spread that
collapses an axis emits nothing. Active clips and layers apply normally; open an
escaping overlay layer before painting a popup whose shadow must escape its parent.

The Metal/GLES fragment shaders evaluate square-rectangle Gaussian integrals
analytically, using an error-function approximation. Rounded rectangles integrate
one axis analytically and use eight fixed midpoint samples along the other.
This is an approximation, based on Evan Wallace's CC0 implementation:
https://madebyevan.com/shaders/fast-rounded-rectangle-shadows/
There are no blur textures, extra render passes, CPU rasterization or shadow cache.
Ordinary and shadow surfaces share batching. Metal reuses previously unused
padding fields, keeping the 80-byte GPU instance stride.

GPU cost depends on covered pixels, overlap and sample count, even though the
number of samples does not grow with blur radius. The first version supports
outer shadows of rounded rectangles, not arbitrary image silhouettes, inset
shadows or blurring an entire widget subtree. Translucent casting surfaces show
the shadow beneath them; the shadow mask is not punched out behind the caster.

`stroke` emits an inward outline with a transparent center. Width zero emits
nothing. It shares the rounded-rectangle distance field and derivative-based
antialiasing used by ordinary surfaces. A focus ring can use an expanded rect
without enlarging a widget's interaction bounds.
