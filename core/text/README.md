# Text layout

The public API lives in `core/text.odin` (package `ui`). Call it during the window
update, like the existing text/rect-cutting functions.

```odin
// Text determines the height of this cut.
paragraph, err := ui.layout_text(value, body_font,
    max_width = ui.current_rect().size.x, size = 18)
assert(err == .None)
ui.open_rect(.Top, paragraph.height)
{
    assert(ui.draw_text_layout(paragraph) == .None)
}
ui.close_rect()

// A fixed button determines the available width for its text.
ui.open_rect(.Top, 56)
{
    ui.paint(color = {0.2, 0.4, 0.7, 1}, corners = 8)
    ui.pad2(0, 12)
    caption, error := ui.layout_text_fit("Save changes", body_font,
        max_width = ui.current_rect().size.x, size = 24, min_scale = 0.5)
    assert(error == .None)
    assert(ui.draw_text_layout(caption, align = .Center, valign = .Center) == .None)
}
ui.close_rect()
```

Both return `Text_Layout` and `Text_Error`. Layout exposes `width`, `height`,
`ascent`, `descent`, `line_count`, effective em `size`, and `overflow`. These are
logical window points. Width means advance width, not ink bounds; height is the
number of lines times the font's line height (including for an empty line).
Drawing consumes no rect space. Horizontal alignment applies to each line;
vertical alignment applies to the whole block. `.Start`/`.End` mean left/right
or top/bottom, independently of reading direction.

`layout_text` greedily wraps at ASCII spaces, trimming spaces at line edges and
preserving interior spaces. LF, CR/CRLF, NEL and U+2029 separate paragraphs.
U+2028 forces a line break within the same bidi paragraph. Blank and trailing
empty lines are preserved. Overlong words stay intact and set `overflow`; no
splitting of combining sequences, ligatures, NBSP groups, or Arabic words.
This first policy is not full UAX #14 line breaking: no CJK word-break rules,
hyphenation, tab stops, or ellipsis. Tabs return `Unsupported_Text`.

`layout_text_fit` keeps a single line, uses the desired size if it fits, and
otherwise scales uniformly down to `min_scale` (default 0.5). Values must be in
(0, 1]. If even that size is too wide, `overflow` is true; the caller chooses what
to do. Only width constrains fitting. The button must have enough height for the
result. Newlines are rejected by this API. Neither path clips text.

## Caching and lifetime

A layout is a lightweight request and measured result, safe to copy. It borrows
the input text and language strings: keep their storage alive and unchanged
until the final draw using that result. There is no destroy call. Recreate it
when text, width, style, or window pixel scale changes; do not use it in another
window. Calling the layout function each frame is the intended immediate API.

The window owns a bounded LRU cache (1,024 entries / 4 MiB of payload shared with
single-line text). Entries own text, glyphs, line ranges, metrics, and lazily
prepared geometry. Drawing looks up the request again, so cache eviction cannot
leave a dangling glyph slice in a retained result. Oversized entries use scratch
storage rather than exceeding the cache budget.

Measurement never rasterizes. First drawing prepares glyph quads and atlas
bitmaps. Unchanged layouts then need only cache lookup and surface placement;
no bidi, shaping, geometry rebuild, or Odin allocation once output capacity is
warm. Position, color and alignment do not affect the cache key.

Wrapping caches the complete result by physical width (rounded down to 1/64 px).
On a miss, SheenBidi resolves each paragraph once; candidate lines use those
levels and HarfBuzz shapes within the selected line boundaries. Exponential
probing and binary refinement avoid measuring every growing word prefix of a
wide paragraph. Each line's visual glyph order is stored alongside its width.

Fitting reuses the desired-size single-line shape and glyph bitmaps across all
widths, applying a uniform scale to geometry and metrics. It does not create a
new atlas font size for every resize step. This is intentionally distinct from
reshaping a variable font with a new optical-size coordinate.

Build/run `./scripts/build.sh app7` and `./bin/app7` for Latin wrapping,
Arabic/English wrapping, and centered labels in differently sized buttons.
