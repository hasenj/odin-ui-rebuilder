# Latin text

Text uses HarfBuzz for shaping and FreeType for grayscale outline rasterization.
No native platform text APIs are used. The first iteration supports one
left-to-right Latin line per call, including kerning, ligatures, combining marks,
and variable-font weight. Arabic/bidi, fallback, wrapping, clipping, color glyphs,
and system font discovery are deferred.

## Build

Use the September 2026 Odin nightly or newer. Install shared native dependencies:

```sh
# macOS / Homebrew
brew install freetype harfbuzz pkgconf

# Omarchy / Arch Linux (in addition to the Wayland/Mesa dependencies)
sudo pacman -S --needed freetype2 harfbuzz pkgconf
```

From the repository root:

```sh
./scripts/build.sh app5
./bin/app5
./scripts/check.sh
```

The build helper passes pkg-config's library search paths to Odin, including
Homebrew's non-default locations. The Odin bindings link system FreeType and
HarfBuzz directly. These shared libraries must also be installed on the machine
running the binary. The app5 fonts are read from files, so run it from the
repository root. Existing examples remain available as app0 through app4.

## Usage

Call UI functions during the window's update. Load fonts once and retain handles:

```odin
font, err := ui.load_font("path/to/font.ttf", name = "body")
assert(err == .None)

ui.open_rect(.Top, 48)
{
    ui.paint(color = {0.1, 0.1, 0.1, 1}, corners = 8)
    ui.pad2(8, 12)
    _, err = ui.text("Hello, café!", font = font, size = 20)
    // A registered string name works too:
    // _, err = ui.text("Hello, café!", font = "body", size = 20)
    assert(err == .None)
}
ui.close_rect()
```

`load_font` also accepts a zero-based `face_index` for collections. If `name` is
omitted, the font's family name is registered. Names are exact, case-sensitive
aliases; duplicate names return `Name_Exists`. Loading a second face in the same
family requires a different alias. `find_font("body")` returns `(Font, bool)`.
There is no implicit lookup of installed fonts or automatic style matching.
Font handles are one-based indices into a window-owned append-only array: O(1)
lookup, no unloading or slot reuse, valid only for that window's lifetime.

`text` emits ordinary image surfaces at the current rectangle's top-left,
without changing the rect or creating layout nodes. Size is the font's em size
in logical window points, not the height of its visible ink. The first baseline
is top + ascent; glyph bearings and HarfBuzz offsets position the ink. Ascenders
or overhangs can extend beyond the nominal line box. Color uses straight RGBA,
just like other surfaces. Empty rects (zero width or height) emit no glyphs, but still return text metrics
and validation errors. This prevents exhausted rect cuts from piling text at
one position. Nonempty rects do not clip text that exceeds their bounds.

```odin
metrics, err := ui.measure_text("Continue", font = "body", size = 16, weight = 600)
assert(err == .None)
ui.open_rect(.Top, metrics.height + 16)
{
    ui.pad(8)
    _, err = ui.text("Continue", font = "body", size = 16, weight = 600)
    assert(err == .None)
}
ui.close_rect()
```

Both calls return `(Text_Metrics, Text_Error)`. Metrics contain `width` (advance
width, including spaces), `height` (line advance), `ascent`, and positive
`descent`, all in logical points. Measurement shapes text but never rasterizes
or uploads glyphs. Missing fonts/glyphs and tabs/newlines produce explicit errors;
this API accepts Latin text and does not automatically segment other scripts.
A failed `text` call leaves no partial surfaces for that call.

Weight 0 selects the font's default. A nonzero value selects the variable font's
`wght` coordinate (for example 450); values outside its axis range return
`Invalid_Weight`. Static fonts or variable fonts without that axis return
`Unsupported_Weight` for nonzero weights. Other variation axes use defaults.
No synthetic bolding is applied. Rasterization uses scalable outlines with
hinting and embedded bitmap strikes disabled.

## Storage and drawing

Each window owns its FreeType library, font faces, HarfBuzz fonts, and a reusable
shaping buffer. The font table and atlas pages are linear arrays. Each font has a
hash map keyed by glyph ID, physical size (1/64 pixel), and weight (16.16).
Display scaling is accounted for before rasterizing, so a Retina display uses
higher-resolution glyphs while layout stays in logical points.

A missing glyph is rasterized once and packed into a 1024×1024 RGBA atlas with a
transparent texel gutter. Glyph coverage is premultiplied white and tinted by
the normal surface shader. Adjacent glyphs using the same atlas share renderer
batches. Dirty regions upload after the UI update; Metal queues staging blits
in order with draws, and GLES uses ordered texture subimage uploads. Warm glyphs
need neither rasterization nor texture upload.

Measurement and drawing share a shaped-run cache. Its key is the font handle,
text contents, physical size (1/64 pixel), and effective variable weight (16.16).
Each entry owns its text, glyph IDs/clusters, positions, and metrics. Color and
screen position do not affect shaping and are not part of the key; display scale
is represented by physical font size. Equivalent physical sizes reuse a run,
with metrics converted to logical points for each call. Language, direction,
and features are fixed in this Latin-only API; if exposed later they must also
become part of the key.

A cache hit skips HarfBuzz and native size/weight changes. A bitmap miss restores
the requested native font configuration before rasterizing. Glyph lookup and
surface emission still run per visible glyph each frame. No API changes are
required: the usual measure-then-draw sequence shares one cached result.

The shaped-run cache has an LRU limit of 1024 entries and 4 MiB of owned text/glyph
data, plus bounded array/hash-map metadata. Entries are stored in a linear array;
LRU links are array indices. New labels evict the least recently used runs as
needed; a run larger than the byte budget is shaped without caching. Input strings
are copied only on cache insertion, so callers may reuse temporary buffers.
Repeated cached calls make no new Odin allocations. Native HarfBuzz allocations
on misses are outside Odin's allocation tracker.

Atlas storage grows on demand to at most 16 pages (64 MiB CPU + 64 MiB GPU,
excluding transient upload storage). It currently has no eviction: many unique
sizes or continuously animated weights can exhaust it and return `Atlas_Full`.
CPU caches/native font objects are released when the window returns; GPU atlas
textures are owned and destroyed by the platform renderer. macOS currently
exits the process when its single window closes.

The example includes Noto Sans Display and Noto Serif Display variable fonts,
copied from the supplied local font collection. Their SIL Open Font License and
copyright notices are in `examples/app5/assets/OFL.txt`.

## Validation

The font test uses the real bundled font files to check shaping, ligatures,
kerning, composed/decomposed accents, variable weights, scale, bitmap coverage,
cache reuse, error handling, and resource teardown. Shaped-run tests cover
mutable input buffers, native size/weight changes, font-table growth, LRU/byte
limits, oversized runs, and allocation-free cache hits. The platform tests render
atlas regions and subregion updates through the actual GPU pipeline and read
back pixels. On Linux they use the existing surfaceless EGL test harness;
`WAYLAND_RENDER_TEST` remains available for the compositor's driver.
