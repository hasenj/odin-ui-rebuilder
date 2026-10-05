# Future work

Created and maintained by Codex (the AI assistant).
Updated 2026-10-05.

Open design directions only. Completed work and implementation status belong in
[PLAN.md](PLAN.md) and the package documentation. Milestone numbers below refer
to that roadmap; they do not prescribe an execution order.

## System fonts and automatic fallback (23)

Discover configurable platform font directories and index minimal face/style
metadata and Unicode cmap coverage. Script labels alone are insufficient.
Avoid eagerly loading or rasterizing every face. Use the index to narrow
candidates on a cache miss, then load suitable faces lazily and validate shaping
for complete clusters/script spans.

Keep explicit font stacks as the first preference, with system fallback available
even when application code provides no fallback list. Retain positive and negative
fallback decisions and resolved glyph runs. Give catalog changes a generation so
old misses can be retried; unchanged frames must never scan installed fonts.
Color emoji and variation-sequence preferences need separate treatment rather
than assuming cmap coverage establishes correct rendering.

## Redraw scheduling (25)

Replace continuous idle updates with invalidation from input, resizing,
application changes and external producers. An invalidation from any window or
panel schedules one shared application update: snapshot all participants, then
run all builders with the same time. Native presentation can remain independently
paced by visibility and compositor readiness.

Animations, caret blinking, tooltip delays and toast expiry need explicit next
update deadlines. Worker file/image completions must wake the application rather
than depend on a periodic UI poll. Allow application code and external GPU
producers to request an update safely, including from another thread.

Account for previous-frame interaction geometry: a newly appearing or moved
region may require a settling update even without another input event. Define
when to request that update without creating an endless redraw loop. Verify
idle work and input latency as well as individual frame execution time.

## Reusable virtual lists (24)

Extract the fixed-height list mechanism into a shared API. Keep work proportional
to the visible range, with bounded extra work for keyboard navigation and reveal.
Use stable application item keys across insertion and reordering.

Define what happens to focus, active editing and retained component state when a
row leaves the declared range. Options include retaining selected interaction
participants or keeping durable state in application data; do not silently promise
that omitted identity nodes persist. Accessibility must be able to represent and
reveal offscreen items without building every row each frame.

Variable-height lists can follow with cached measurements, estimated extents and
scroll anchoring. Preserve the visible item and its relative offset when earlier
rows change height or are inserted, rather than letting the viewport jump.

## Editing extensions (38)

Improve Unicode word boundaries, typing undo coalescence and ligature caret
positions. Evaluate OpenType caret information where available; keep sensible
fallbacks when fonts omit it.

For multiline editing, use the same wrapped layout for rendering, hit testing,
selection and caret movement. Vertical movement should retain a preferred X
position across short lines. Define visual versus logical movement at bidi and
wrap boundaries, scrolling/reveal, composition across lines and large-document
limits. Keep single-line field behavior independent of multiline policy.

Richer native character-range geometry and selective macOS panel keyboard focus
can follow concrete editing needs. A mouse-only palette could leave the main
window key while a panel text field requests keyboard focus; this is an optional
refinement, not a reason to fake the main window's active decoration state.

## Accessibility (31)

Let components declare roles, names, values, actions and bounds under stable
identities. Connect semantic focus to keyboard focus, clipping, scrolling and
virtualized content. Bridge this data to native accessibility APIs with separate
verification per platform. Start with the standard controls and a screen-reader
example before expanding the widget API substantially.

## Native window controls and placement (39)

Add minimize/restore/show/hide controls and screen/work-area information, with
explicit backend capabilities. Preserve main-window ownership of application
lifetime and the shared update cycle, even when a participant is minimized.

One motivating flow is to minimize the main window, show a transparent
undecorated auxiliary surface for an area-selection HUD, then close it and
restore the workspace. Desktop capture and OCR are separate application features.
Respect Wayland restrictions on placement and activation; avoid promising an
identical global-coordinate model on every platform.

A declarative begin/end-window convenience API remains a possible later layer.
Define omission, hiding, destruction and reopening semantics before adding it;
it must preserve explicit native lifetimes and the main-window/panel model.

## File watching and image loading extensions (32)

Use native filesystem notifications if metadata polling becomes a bottleneck,
and connect worker completions to redraw scheduling. Consider refreshing directory
entry metadata when an existing child's contents change, without requiring an
addition/removal in the directory.

Consider byte-based image cache budgets, additional formats, full-size previews
and explicit resource pinning for application-controlled retention. Keep decoding
and reduction off-thread, GPU resource changes on the owning renderer thread,
and resource lifetime explicit through reload, eviction and window teardown.

## External GPU content and engine integration — future direction

The useful abstraction is an image resource whose pixels are produced elsewhere.
Layout still places it in a rect; the renderer samples a compatible GPU resource
without first reading its pixels to the CPU and uploading them again.

Video is one producer. Supported codecs can decode through dedicated hardware
into GPU-readable buffers. Some CPU work remains for file/stream processing,
timing and coordination; unsupported decode configurations can use software.
For macOS, the proposed starting path is AVPlayer + AVPlayerItemVideoOutput,
CVPixelBuffer/IOSurface storage, and CVMetalTextureCache. Video color conversion
and metadata, including eventual HDR support, require deliberate handling.

Playback advances independently of UI frame construction. Reuse the current
video frame when no newer frame is due. Avoid CPU pixel uploads on each update.

A game engine is another producer. Support both integration directions:

1. Import the engine's rendered texture and paint it in a UI rect or as a
   background, with UI surfaces above it.
2. Render the UI into a transparent texture that the engine composites over its
   game or uses on a surface within a 3D scene.
3. Allow the engine to invoke our renderer directly on its existing render
   target for a HUD pass, avoiding an intermediate UI texture/compositing pass.

For all of these, agree on resource ownership, resize/replacement, pixel format,
color space, alpha convention, and synchronization. The producer cannot overwrite
a buffer while a consumer's GPU commands still read it. Retain resources until
GPU completion; buffer pools and GPU-side synchronization can avoid CPU waits.
Separate processes are not required. Cross-process or cross-API sharing needs
additional backend-specific mechanisms.

## Cross-platform separation

Target Windows, macOS, Linux/Wayland, iOS, and Android.

Keep these responsibilities separable as the project grows:

| Part | Responsibility |
| --- | --- |
| UI core | Layout, identities, state, text layout, and drawing commands |
| Renderer backend | GPU resources, drawing, external images, and render targets |
| Platform backend | Native windows/views, input, display timing, and lifecycle |

Platform and renderer are not necessarily a fixed pair. An engine may supply its
own window, device, and frame loop. It should be able to build our UI and invoke
a compatible renderer without our platform backend creating a window or owning
the application loop.

Keep the UI-facing contract portable, while exposing explicit backend-specific
integration points for native GPU resources and synchronization. Metal textures
and Vulkan images are not interchangeable handles. Desktop decorations and
movable windows must not become core requirements; on mobile the host view and
application lifecycle provide the relevant environment.
