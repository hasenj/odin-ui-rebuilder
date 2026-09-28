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

// A fixed button determines the available width and height for its text.
ui.open_rect(.Top, 56)
{
    ui.paint(color = {0.2, 0.4, 0.7, 1}, corners = 8)
    ui.pad2(6, 12)
    caption, error := ui.layout_text_fit("Save changes", body_font,
        max_width = ui.current_rect().size.x,
        max_height = ui.current_rect().size.y,
        size = 24, min_scale = 0.5, wrap_at_min = true)
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

`layout_text_fit` starts with a single line, uses the desired size if it fits,
and otherwise scales uniformly to fit `max_width` and optional `max_height`,
stopping at `min_scale` (default 0.5, valid range (0, 1]). Height is unconstrained
when omitted; supplied limits must be finite and nonnegative.

With `wrap_at_min = true`, a line that still exceeds the width at minimum size
uses the same word-wrapping policy as `layout_text`. Wrapping keeps that minimum
size; it does not enlarge the text afterward or shrink below the minimum to fit
extra lines. `overflow` reports whether the final width **or height** exceeds its
limit. Wrapping is disabled by default, preserving single-line behavior.
Newlines are rejected by this API. Neither path clips or truncates text.

## Caching and lifetime

A layout is a lightweight request and measured result, safe to copy. It borrows
the input text and language strings: keep their storage alive and unchanged
until the final draw using that result. There is no destroy call. Recreate it
when text, constraints, style, or window pixel scale changes; do not use it in another
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

Wrapping uses a second bounded LRU cache for paragraph preparation: up to 256
paragraphs / 4 MiB, including owned buffers and an allowance for retained native
bidi state. It is keyed by text, font, physical size, weight, direction and
language, **without width**. It retains SheenBidi paragraph analysis, script runs,
HarfBuzz glyphs and cluster boundaries, and exact 26.6 prefix advance sums.
Oversized paragraphs are prepared in temporary storage rather than retained.

A new width searches those prefix sums for line breaks. Each selected line is
reordered with SheenBidi's line rules, then assembled from the cached glyph runs;
RTL glyph clusters and their internal mark order remain intact. HarfBuzz's
`UNSAFE_TO_BREAK` flag prevents splitting cached shaping at an unsafe boundary.
Those boundaries, or line-specific direction changes incompatible with the
cached runs, use exact line reshaping. In the ordinary Latin/Arabic word-wrap
path, resizing needs no new shaping or paragraph analysis.

The final wrapped output and geometry are still cached by physical width
(rounded down to 1/64 px). A previously unseen width builds its own line ranges
and geometry; an unchanged width uses the complete cached result.

Tests compare glyph IDs, source clusters, advances, offsets, line breaks and quad
positions against the original exact line shaper across widths and bidi cases.
`./scripts/bench-text-resize.sh` measures preparation plus geometry over 240 new
widths for the app7 Latin/Arabic paragraphs, after font/atlas warm-up. It reports
CPU time and the new shaping/paragraph-analysis call counts, excluding GPU waits.

Fitting reuses the desired-size single-line shape and glyph bitmaps across all
widths, applying a uniform scale to geometry and metrics. Its wrapping fallback
converts the width to those original font coordinates and uses the paragraph
and wrapped-layout caches described above. It does not create a new atlas font
size for every resize step. This is intentionally distinct from reshaping a
variable font with a new optical-size coordinate.

Build/run `./scripts/build.sh app7` and `./bin/app7` for Latin wrapping,
Arabic/English wrapping, and centered labels in differently sized buttons.
