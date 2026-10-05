# Future work

Created and maintained by Codex (the AI assistant).
Updated 2026-10-05.

Future design details and acceptance criteria live here. [PLAN.md](PLAN.md)
tracks milestone scope, status and priority; package docs describe completed APIs. Milestone numbers below refer
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

**Acceptance:** an app naming its preferred font displays and edits mixed-script
text with suitable installed fallbacks, consistent measurements and bounded
warm-frame work, without configuring every fallback face itself.

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

**Acceptance:** idle windows generate no regular UI frames, while input,
resizing, scrolling, animations and explicit invalidation remain responsive.

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

**Acceptance:** a second app uses the shared API without duplicating range or
navigation logic. Tests cover focus and durable state through scrolling,
insertion and reordering before extending to variable heights.

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

**Acceptance:** a multiline example supports mixed-script text, wrapping,
selection, clipboard, undo/redo and IME during resizing and scrolling, with
cached unchanged geometry and explicit document-size limits.

## Accessibility (31)

Let components declare roles, names, values, actions and bounds under stable
identities. Connect semantic focus to keyboard focus, clipping, scrolling and
virtualized content. Bridge this data to native accessibility APIs with separate
verification per platform. Start with the standard controls and a screen-reader
example before expanding the widget API substantially.

**Acceptance:** a screen reader navigates an example, announces and edits values,
invokes actions and follows focus/scroll changes through a native adapter.

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

**Acceptance:** an example exercises minimization, auxiliary-surface interaction
and restoration without breaking application ownership or synchronized updates.
OS minimization must not imply skipping UI construction.

## File watching and image loading extensions (32)

Use native filesystem notifications if metadata polling becomes a bottleneck,
and connect worker completions to redraw scheduling. Consider refreshing directory
entry metadata when an existing child's contents change, without requiring an
addition/removal in the directory.

Consider byte-based image cache budgets, additional formats, full-size previews
and explicit resource pinning for application-controlled retention. Keep decoding
and reduction off-thread, GPU resource changes on the owning renderer thread,
and resource lifetime explicit through reload, eviction and window teardown.

## External GPU content and engine integration (26)

The useful abstraction is an image resource whose pixels are produced elsewhere.
Layout places it in a rect; the renderer samples a compatible GPU resource
without first reading its pixels to the CPU and uploading them again.
Support three integration paths:

1. Import an engine's rendered texture and paint it in a UI rect or as a
   background, with UI surfaces above it.
2. Render UI into a transparent texture for the engine to composite or use
   on a surface within a 3D scene.
3. Invoke our renderer directly on the host's existing render target for a HUD,
   preserving its contents and avoiding an intermediate compositing pass.

Define resource ownership, resizing, pixel format, color space, alpha convention
and producer/consumer GPU synchronization. A producer cannot overwrite a buffer
while a consumer's GPU commands still read it. Retain resources until completion;
buffer pools and GPU-side synchronization can avoid CPU waits.

Begin with same-process Metal integration and a backend-neutral contract for
other graphics APIs. Separate processes are not required; cross-process and
cross-API sharing can follow with backend-specific mechanisms.

**Acceptance:** a host-driven example exercises all three paths and resizes
safely without our library owning its window/event loop or transferring complete
frames through CPU memory.

## Video as an external image producer (27)

Build on 26. Supported codecs can decode through dedicated hardware into
GPU-readable buffers. Some CPU work remains for processing, timing and
coordination; unsupported decode configurations may use software.

Start on macOS with AVPlayer/AVPlayerItemVideoOutput, compatible CVPixelBuffer/
IOSurface storage and CVMetalTextureCache. Advance playback independently of UI
construction, reuse a frame when no newer one is due and retain buffers through
GPU completion. Handle audio synchronization, seeking and color conversion.
Start with SDR; HDR and other platform playback backends can follow separately.

**Acceptance:** video plays inside a clipped UI region with overlays, pauses and
seeks correctly, without an application-side full-frame CPU upload each update.

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

### Windows desktop (28)

Implement native windows, rendering, main/panel lifecycle, input, focus,
clipboard/composition, scaling and presentation behind the common interfaces.
Choose the graphics backend explicitly and document capability differences.

**Acceptance:** shared examples and interaction/editing checks run on Windows,
including multiple windows and display-scale changes.

### iOS host views (29)

Define portable touch data first, then add a host application/view lifecycle
adapter, Metal rendering, touch/pointer input, software-keyboard/composition,
display scaling and safe-area data. Handle foreground/background transitions;
neither desktop windows nor ownership of the host loop can be prerequisites.

**Acceptance:** a host iOS app embeds the UI, edits text, scrolls by touch and
survives rotation, keyboard appearance and suspension/resume.

### Android host views (30)

Reuse the mobile lifecycle/input contracts from 29 with Android-specific
surface, graphics, touch, keyboard/composition and clipboard adapters. Choose
the graphics backend and handle density changes and surface loss/recreation.

**Acceptance:** the host example supports touch scrolling and editing through
surface recreation and foreground/background transitions.

## Other optional extensions

- Rounded/path clipping, arbitrary shadow silhouettes, inset shadows and
  subtree/backdrop blur can follow concrete rendering needs. Keep them separate
  from rect-cutting geometry and avoid corner-radius inheritance machinery.
- Grow the file manager beyond its first read-only version with file opening,
  file operations, full-size previews or richer search as needed.
