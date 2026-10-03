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

Click a blue folder name to enter it; Up returns to its parent. Wheel/trackpad
scrolls the list. Tab focuses folders or Up; Enter/Space activates them. Files
are displayed only. Hidden entries are included. Folders appear first, with
case-insensitive alphabetical ordering within each group.

Directory snapshots are read synchronously on navigation and retained between
updates. Navigating resets scrolling. Failed navigation leaves the existing
listing visible with an error. The virtual list builds only visible rows plus
at most five offscreen keyboard focus targets (current folder, neighbors,
first/last folder). Tab/Shift-Tab still traverse folders in order and reveal
the destination, even after manual scrolling.
Per-frame row work depends on viewport height, not the directory entry count.
Very large or remote directories can still pause while being read; asynchronous
directory scans and filesystem watching are future improvements.

The sample uses the bundled Latin font. Names containing unsupported glyphs or
control bytes fall back to byte escapes; navigation always uses the original
name. Long names and paths are clipped. System-font fallback, previews, file
operations, selection and search are not part of this first version.
