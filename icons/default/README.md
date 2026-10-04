# Default icons

Created and maintained by Codex. The ten SVG designs here are original artwork
made for this repository, not copied from Remix, Phosphor, or another collection.

The checked-in `icons.ttf` is 2,332 bytes. `src/` contains editable filled paths
on a 24×24 grid, with consistent rounded strokes. `manifest.json` assigns stable
Unicode private-use code points. Append new entries without renumbering existing
ones. Glyph indices are deliberately resolved when a window loads the font.

```odin
import icons "path/to/icons/default"

// During window update, once per window; keep the set in window-owned state.
set, err := icons.load()
close := set[.Close] // ui.Icon_Glyph {font, glyph}
_ = ui.draw_icon(close, destination, color)
if w.button("Close", icon = close) { /* ... */ }
```

`widgets.begin` already manages the default set automatically. Other icon
packages need only load a physical font and call `ui.resolve_icon(font,
codepoint)` to supply the same `ui.Icon_Glyph` type. They do not depend on widgets.
Icon glyphs refer to a window-owned font, not a process-global font ID.

## Regenerating

Normal builds need no Python, font tools, or installed icon fonts. The tiny font
is embedded and loaded from owned memory. To edit/add source outlines:

```sh
python3 -m venv bin/icon-tools
bin/icon-tools/bin/pip install fonttools==4.60.1
bin/icon-tools/bin/python icons/default/generate.py
```

The generator reads the manifest and SVG paths, builds the TTF and Odin catalog,
and uses a fixed font timestamp for reproducible output. Paths must be filled
outlines; convert strokes/transforms/groups to paths before adding artwork.
Check in the SVG, manifest, generated font and `catalog.odin` together.

Rendering fits the glyph's ink into a requested box while retaining aspect
ratio; the atlas includes transparent antialiasing padding. Lookup/rasterization
is cached. A warm icon draw emits a single textured surface without shaping.
