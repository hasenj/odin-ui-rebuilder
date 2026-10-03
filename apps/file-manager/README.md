# Files

A minimal, read-only file browser built with rect cutting, clipping, scrolling,
hover animation and focus. From the repository root:

```sh
./scripts/build.sh file-manager
./bin/file-manager                 # Home directory
./bin/file-manager /path/to/folder # Optional starting directory
./bin/file-manager --capture       # Navigation/virtual-list checks and PNGs in bin/
./bin/file-manager --bench         # Warm update timings for 20 / 2,000 / 20,000 rows
```

Click a folder row to enter it; the Up arrow returns to its parent. Wheel/trackpad
scrolls the list. Tab focuses entries or Up; Enter activates directories. Files
can be selected but are not opened. Hidden entries are included. Folders appear first, with
case-insensitive alphabetical ordering within each group.

Directory reads and sorting run on a worker. The browser tracks None / Reading /
Done and keeps the last successful listing while a new one loads. Failed
navigation leaves it visible with an error. Directory metadata is watched on
the worker roughly every 250 ms; additions/removals trigger a new snapshot.
Navigation resets scrolling; a refresh preserves and clamps the current offset.
Focus is cleared on snapshot replacement to avoid activating a different file
at a reused row index.

PNG/JPEG rows load thumbnails by path with `ui.image_file(..., max_extent = 128)`.
Reading, decoding, thumbnail reduction and change checks all run off-thread;
the UI uploads completed pixels. Modified images reload automatically while
keeping the last successful texture visible. Loading rows show `...`; failed
initial loads show `!`. See [the image API](../../core/IMAGES.md) for cache lifetime
and [the worker service](../../core/files/README.md) for polling limitations.

The virtual list builds only visible rows plus at most five offscreen keyboard
focus targets (current entry, neighbors, first/last entry). Tab/Shift-Tab
traverse entries in order and reveal the destination, even after manual
scrolling. Per-frame row work depends on viewport height, not entry count.

The default design is compact and dark, with 30-point rows, one address bar,
an integrated Close button, and no native title bar. The initial window is
640×480; it also fits 400×360 and 320×240 tiles. Kind disappears below 564 points
of window width, and Size below 324; filenames retain their font size. The
footer shows counts, an active find prefix, or an error/loading state.
The address replaces the home directory with `~` and reveals the tail of long
paths. On macOS, drag the address area to move the window; file rows and the
Up/Close controls never start a window drag. Command-Q also quits. Wayland
window movement continues to use compositor bindings; native Wayland drag
regions are not implemented here.

The [approved dark mockup](design/compact-dark.png) and its
[generation prompt](design/compact-dark-prompt.txt) are saved alongside the
original design. `--capture` verifies navigation, watched directory updates,
type-to-select and 20,000-row virtualization, and writes actual GPU captures:
`bin/file-manager-design.png`, `bin/file-manager-compact.png` (400×360), and
`bin/file-manager-small.png` (320×240). A thin scrollbar indicates position;
use wheel/trackpad or keyboard to scroll (the indicator is not draggable).

Type a filename prefix to select and reveal it, e.g. `dow` selects Downloads.
Matching uses Unicode simple case folding; it does not normalize accent forms or
perform fuzzy/substring matching. One second of inactivity starts a new prefix.
Backspace shortens it; Escape clears it. Repeated single letters cycle matching
entries when the repeated-letter prefix has no match. A failed search leaves
selection unchanged. The footer shows the prefix and whether it matched.
Typing Space is part of the prefix, not folder activation. Native text input
supports the active layout, dead keys and IME; composition stays on its current
focus target until committed. A new directory snapshot clears the prefix.

Matching scans filenames only when the prefix changes; unchanged frames do no
search work. Results are scrolled into view before building the visible rows,
keeping the same virtualization bounds. Native type-to-select currently needs
the macOS text-input adapter; the Wayland adapter remains separate work.

The sample uses the bundled Latin font. Unsupported glyphs display as tofu;
invalid/control-containing names fall back to byte escapes. Navigation/matching
always uses the original name. Long names and paths are clipped. System-font
fallback, full-size previews, file operations and content search remain future work.
