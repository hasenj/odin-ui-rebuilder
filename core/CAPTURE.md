# Render capture

`ui.capture_frames` runs the normal UI builder against an offscreen GPU target
and writes PNG files. The first backend is macOS Metal. It needs a Metal-capable
Mac, but no native window, desktop screenshot permission, or event loop. Other
platforms return `Unsupported` for now; their normal windows are unchanged.

## Capture an existing example

From the repository root:

```sh
./scripts/capture.sh app9 bin/app9.png
./bin/capture app7 bin/app7-narrow.png 600 880 2 0
./bin/capture app8 bin/app8-hover.png 960 640 2 0 56 120
```

The script builds an optimized `bin/capture`. The runner supports app4 through
app11, importing their existing update procedures. Arguments after the output
path are optional width, height, scale, and time; supply both mouse coordinates
to simulate a pointer inside the window. Default dimensions match each example,
scale is 2, and time is 0. Relative paths are resolved from the repo root when
using the script. Output directories must already exist. Existing output files
are overwritten. Failures print the error and exit nonzero.

Each invocation starts a new process, so the example's globals and font/image
handles start fresh. Identity-based hover uses prior geometry, so a first-frame
capture has no resolved hover. Use a sequence with a warm-up update to inspect hover transitions.

## Drive a sequence

```odin
frames := [?]ui.Capture_Frame{
    {path = "bin/normal.png", size = {960, 640}, scale = 2},
    // Advance state without saving. Establish hover at time zero.
    {size = {960, 640}, scale = 2,
     input = {mouse_inside = true, mouse_position = {56, 120}}},
    {path = "bin/transition.png", size = {960, 640}, scale = 2, time = 0.03,
     input = {mouse_inside = true, mouse_position = {56, 120}}},
    {path = "bin/settled.png", size = {960, 640}, scale = 2, time = 1,
     input = {mouse_inside = true, mouse_position = {56, 120}}},
}
result := ui.capture_frames(update, frames[:])
assert(result.error == .None)
```

Call outside a UI update, on the main thread. Each call owns a fresh UI state and
renderer. Identity, animation, font, image and text caches persist across the
sequence, and are released when the call returns. Initialize application-owned
state for that session: never reuse cached font or image handles from a window
or an earlier capture call. Capture does not reset the application's globals.

Input is a complete snapshot for each frame. Time is explicit, nonnegative,
finite and nondecreasing (equal timestamps are allowed); no real-time sleeps
are involved. Scale must be positive and explicit. The PNG dimensions are
`ceil(size * scale)`, up to 16384 pixels on each axis. An empty path runs the UI
update and atlas uploads but skips rendering/readback/file writing.

The optional `clear_color` is straight RGBA and defaults to transparent. Use
`{0.035, 0.045, 0.065, 1}` to reproduce the opaque window background. Saved PNGs
are top-to-bottom RGBA8 with straight alpha; capture converts Metal's
premultiplied BGRA output before encoding. Encoding uses Odin's bundled
`vendor:stb/image` writer, with no additional installation step.

`Capture_Result.error` reports validation, GPU rendering, or file write errors.
`frame_index` identifies the failing frame (zero-based), or is -1 on success or
an unsupported backend. The complete sequence is validated before updates run.
If rendering/writing fails later, earlier output files remain. Renderer startup
and application assertions behave as they do in the ordinary window path.

## What this verifies

Capture uses the production surface encoder, shaders, blending, images and text
atlases. Saved frames synchronously wait for GPU completion. This cost is only
incurred by capture; normal window rendering has no capture work or added waits.
It captures UI content, including alpha, rather than native decorations or the
desktop beneath transparent regions. Native presentation, compositor behavior
and window resizing transactions still need separate window-level checks.

The macOS core integration test renders a multi-frame scene, decodes the PNGs
with Odin's PNG decoder, and checks dimensions, alpha/color, image orientation,
text coverage, retained hover animation, frame clearing, and error reporting.
Exact glyph pixels can vary with fonts and rasterizer versions; visual captures
are evidence, not a promise of identical pixels on every GPU/platform.
