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

Click a teal folder name to enter it; Up returns to its parent. Wheel/trackpad
scrolls the list. Tab focuses folders or Up; Enter/Space activates them. Files
are displayed only. Hidden entries are included. Folders appear first, with
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
focus targets (current folder, neighbors, first/last folder). Tab/Shift-Tab
traverse folders in order and reveal the destination, even after manual
scrolling. Per-frame row work depends on viewport height, not entry count.

The light theme follows an [image-generated reference](design/reference.png);
the [generation prompt](design/README.md) is saved with it. `--capture` writes
`bin/file-manager-design.png` with real thumbnails and verifies directory
watching, scroll preservation, navigation, and 20,000-row virtualization.

The sample uses the bundled Latin font. Names containing unsupported glyphs or
control bytes fall back to byte escapes; navigation always uses the original
name. Long names and paths are clipped. System-font fallback, full-size previews, file
operations, selection and search are not part of this first version.
