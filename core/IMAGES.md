# Images

Call image APIs from a window's UI update. The renderer owns GPU resources;
handles belong to that window and use generational slot lookup.

## Images by path

```odin
ui.open_rect(.Top, 180)
ui.paint_image("pictures/coast.png", corners = 8)
ui.close_rect()
```

`paint_image` requests an image on first use and emits no image surface until
it is ready. Subsequent frames reuse it. PNG/JPEG file reading, decoding, and
optional thumbnail reduction run on a worker. GPU upload happens during a
later UI update, on the renderer's thread.

For custom sizing or loading/error UI:

```odin
asset := ui.image_file(path, max_extent = 128)
if asset.image != (ui.Image{}) {
    size, valid := ui.image_size(asset.image)
    // Use size to choose an aspect-preserving destination if desired.
    ui.paint(img = asset.image)
} else if asset.state == .Reading {
    // Loading placeholder.
} else if asset.error != "" {
    // Failed initial load.
}
```

`Load_State` is `None`, `Reading`, or `Done`. Done includes failure; inspect
`error`. Returned image/error data describe the most recently consumed result;
worker completion can arrive between calls and be consumed on the next frame.
The default `max_extent = 0` keeps original dimensions. A positive extent limits
the longest side while preserving aspect ratio and downsamples off-thread.
`paint_image` uses the same stretching/tint/corner semantics as `paint`.

Watching is enabled by default. The worker polls file metadata about every
250 ms and reloads on modification, deletion/recreation, or atomic replacement.
The previous successful texture remains visible during loading and on failure.
A subsequent file change retries a failed load. Pass `watch = false` for a
one-shot request; its result remains cached until eviction/window teardown.

The cache is per-window, keyed by the supplied path string, `watch`, and
`max_extent`. Relative paths use the process working directory; keep it stable.
Different spellings of the same path are separate entries. It retains up to
128 entries, evicting least-recently-used entries not used in the current frame.
If every entry is pinned, a new request returns Done with a cache-full error.
Updates are consumed at most once per image per frame, so a later call cannot
invalidate an image emitted earlier in that frame.

Cache handles and error strings are borrowed: call the helper each frame;
do not destroy them or retain them across eviction. After eviction, reload, or
window closure, old generational handles become invalid. Use the explicit
loading API below when application code needs to control resource lifetime.

## Explicit ownership

`load_image(path)` and `load_image_from_bytes(bytes)` synchronously decode and
upload, returning `(Image, Image_Error)`. Load once, retain the handle, and call
`destroy_image(&image)` when finished. `image_size(image)` returns the uploaded
pixel dimensions and false for stale handles. Renderer teardown releases all
remaining GPU images.

All loaders currently support 8-bit PNG/JPEG. Animated images, additional
formats, system asset catalogs and shared textures across windows are separate
features. The asynchronous cache uses the service described in
[files/README.md](files/README.md).
