# Future work

Created and maintained by Codex (the AI assistant).

Ideas and design directions for upcoming work, not a milestone plan.

## Input, focus, and hover

Treat input as shared data that any code can read. Do not require dispatched
events, callbacks, or exclusive consumption. Components normally check focus
or hover before reacting, but raw input remains accessible regardless.

Extend the input snapshot with per-frame pressed/released flags, key state,
modifiers, accumulated text input, and scroll deltas. The platform can accumulate
transitions between updates without imposing an event-dispatch model on the UI.
Text input is distinct from physical key input.

Use the identity tree for focus and resolved hover:

- One node is directly focused; its ancestors are indirectly focused.
- Focus can be acquired through clicking or Tab traversal.
- A focus fence limits Tab traversal to descendants of its holder. Nested
  fences, focus restoration, and disappearance of the focused node need explicit
  policies when implemented.
- One node is directly hovered: the eligible node under the pointer with the
  highest effective z-order and then greatest depth.
- Ancestors are indirectly hovered if their own hit regions also contain the
  pointer. Overlays may extend outside their logical parent's geometry.
- Direct versus inherited focus/hover should be distinguishable in the API.
- Hit regions must refer to assigned or explicitly registered geometry, not the
  parent's exhausted remainder after all child cuts.
- Hit-test participation and keyboard focusability are separate properties.

A component can implement dragging by recording that a press started a drag and
continuing to read pointer state until release, even after hover is lost. Do not
require framework-exclusive pointer capture for this. Obtaining movement/release
outside the native window still requires appropriate platform behavior.

### Previous-frame interaction geometry

Use the previous completed frame's tree/geometry to resolve immediate-mode
interaction. This is the chosen way to handle later-declared overlays without
requiring a separate UI declaration pass before reading hover.

The initial proposal resolves the hovered node at frame end for the next update.
A suggested refinement is to resolve the latest input at frame start against
the previous completed geometry, avoiding an extra frame of stale pointer
coordinates. Exact timing remains to be pinned down during implementation.

Latest declaration order is the proposed final tie-breaker for nodes with equal
z-order and depth. Focus traversal eligibility and which focusable ancestor to
choose when clicking a non-focusable descendant also need definition.

## Clipping, scrolling, layers, and remaining foundations

Rectangular clip scopes and coordinate offsets are the first foundations for
scrolling. Scrolling adds retained offsets, content/viewport extents, clamping,
wheel/trackpad input, and nested-scroll behavior. Ordinary hit testing must
respect effective clipping as well as rendering. Scrollbars can come later.

Fixed-height virtual lists can follow scrolling: calculate visible rows and
build that range. Variable-height virtualization requires cached measurements
and scroll-position preservation. Neither is required for the first usable UI.

For overlays, keep logical parentage separate from visual layers. A popup may
remain a descendant for focus purposes while drawing outside its parent's clip
and above unrelated content. Layer/clip escape rules still need an API.

Ordered layer buckets are the preferred initial rendering direction: append
surfaces within each layer in declaration order, then visit layers in order.
Avoid sorting every surface if sorting a small set of layers suffices. A depth
buffer does not replace ordering for translucent UI, nor does it solve input
targeting. Layer buckets remain a proposal to evaluate.

Drawing order does not automatically determine keyboard focus. Tooltips, menus,
and modals have different interaction policies. A Tab fence alone does not make
a modal; pointer blocking outside it and focus restoration also matter.

Other building blocks to revisit:

- General typed component-state storage, guided by scroll offsets, selection,
  and other concrete needs.
- Localized content-sizing layout that measures a component and feeds its
  resolved dimensions into rect cutting, without turning the identity tree
  into a layout tree.
- System-font discovery, metadata indexing, and automatic font fallback.
- Application-defined native window drag regions.
- Text editing: grapheme-aware movement/deletion, caret hit testing, selection
  geometry, clipboard, and IME composition/candidate positioning.
- Redraw-on-demand and animation scheduling instead of continuous idle redraw.
- Accessibility integration.

## Multiple windows — next intended implementation

Prefer explicit native-window lifetime, with one update procedure per window.
The UI inside each window remains immediate-mode. Creating a window must not
start a nested event loop; one application event loop manages all windows.

Conceptual API, not an existing interface:

```odin
ui.init()
defer ui.shutdown()
window := ui.create_window("Workspace", 960, 640, draw_workspace)
ui.run()
// Later: ui.request_close(window)
```

Creation specifies the initial size. Subsequent OS/user resizing should not be
overwritten every frame. Window handles should be generational, and destruction
requested during an update should wait until the callback is finished.

Each window owns its frame, rect stack, identity tree, state and rendering
context. The implicit current context switches for its update callback. Windows
may redraw at different times. Define resource ownership and cross-window
sharing for images and fonts.

A declarative begin/end-window layer remains possible later, but is not the
initial approach. Its omission/hiding/destruction/reopening semantics would
need separate decisions. Also decide whether the application exits or remains
alive when the final window closes.

## Images by path

First, provide an immediate-mode image helper that accepts a filename/path.
Cache a resource record per path: queue a worker decode on first use, emit
nothing while loading, and draw the cached image once ready. Do not read or
decode the file every frame. Keep GPU upload/resource replacement on the
renderer-owning thread, and define failure/retry and resource-lifetime policies.

As a follow-up, watch the filesystem and reload modified images on a worker.
Keep the last successful image visible until its replacement is ready; handle
rapid edits and stale worker results without replacing newer content.

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
