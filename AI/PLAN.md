This file is maintained by the human programmer (Hasen). Do not edit it unless explicitly requested to.

Milestone expansion below written by Codex at Hasen's explicit request on
2026-09-30. [IDEAS.md](IDEAS.md) contains the supporting future-work discussion.
Milestone numbers identify work packages, not example app numbers. Completed
work after milestone 3 is grouped retrospectively; future ordering is proposed.
Updated by Codex at Hasen's request on 2026-10-05 to reflect implementation
through demo16, the file-manager app, and the Omarchy backend updates. Numbers
remain stable even where work was completed out of order; new work packages are
appended below. DONE describes the implemented scope, not every possible
extension. Platform verification limits are called out separately. This update
reviews implementation, tests and recorded validation; it is not a fresh run of
the full macOS or Linux check suite.

## Project Description:

UI framework where the whole UI is reconstructed each time we update the UI

    [Application Data] -> [UI Structure] -> [Rendering Primitives] -> [Screen Pixels]

The framework provides the API to build the UI structure, then at a later pass
produces the rendering primitives and renders them to the screen.

An implementation of this idea already exists in go.hasen.dev/shirei

This project implements the same paradigm in Odin

## [ DONE ] Milestone 0: Basic structure

Odin project structure, a general platform package, and a native macOS window.
Core depends on the platform package interface rather than a specific backend.

## [ DONE ] Milestone 1: Rendering primitives

GPU-rendered surfaces with colors, rounded corners, alpha blending, batching,
and continuously rebuilt frames, using Metal on macOS.

## [ DONE ] Milestone 2: Input as data

Pointer position, pointer-inside state, and held left/right button flags exposed
as a readable frame snapshot. Keyboard, transitions, and scrolling were added in milestone 13.

## [ DONE ] Milestone 3: Images

PNG/JPEG loading, alpha-aware image painting, generational resource handles,
and image-size queries. Demo3 demonstrates images and pointer interaction.

## [ DONE ] Milestone 4: Linux / Wayland backend

Native Wayland windows and pointer input, EGL and GLES 3.0 rendering, image
resources, integer output scaling, and compositor frame callbacks. Shared core
and example code runs on macOS and Linux. Omarchy testing established the GLES
path after desktop OpenGL failed in the VM.

## [ DONE ] Milestone 5: Rect cutting and immediate painting

Implicit frame context, `open_rect`/`close_rect`, padding, geometry queries,
and `paint`. Cuts resolve geometry immediately; painting emits surfaces without
creating layout elements. The earlier flexbox experiment was replaced rather
than retained alongside cutting. Demo4 demonstrates this model.

## [ DONE ] Milestone 6: Font loading and Latin text

FreeType and HarfBuzz, explicit font files and names/handles, variable font
weights, measurement, and GPU glyph atlases. Cached shaping and prepared glyph
geometry avoid repeating work during unchanged frames. Demo5 demonstrates text.

## [ DONE ] Milestone 7: Arabic and bidirectional text

SheenBidi paragraph analysis integrated with script shaping, visual ordering,
Arabic joining/diacritics, and mixed Arabic/Latin/numeric text. Demo6 demonstrates
both base directions. Editing and explicit font fallback were added separately in 21 and 23.

## [ DONE ] Milestone 8: Wrapped and fitted text

`layout_text` wraps paragraphs; `layout_text_fit` shrinks a label to a minimum
size, optionally wraps there, and checks width and height limits. Paragraph
preparation is cached independently of width so normal resizing reuses shaping
and bidi analysis. Demo7 demonstrates wrapping, fitting, and centered labels.

## [ DONE ] Milestone 9: Hover, logical identities, and animation

Rect-level hover queries; a retained identity tree using parent, explicit integer
or caller-location key, and per-key occurrence; generational node handles; and
retained float animation. Distinct integer types remain distinct keys. Demo8
demonstrates independently animated hover colors. Overlap-aware hover and focus were added separately in 15 and 16.

## [ DONE ] Milestone 10: Transparent windows and decoration options

Demo9 demonstrates unpainted transparent regions, translucent surfaces, and
moving shapes. macOS supports transparent and borderless windows, native
background dragging, and Command-Q. Wayland supports transparent windows and
requests decoration preferences through `xdg-decoration`; the compositor can
override the decoration mode. Transparency defaults on for macOS and off for
Linux. Renderer transparency does not define a custom pointer input region.

## [ DONE ] Milestone 11: Frame instrumentation and resize fixes

Optional frame-wall, update, submission, and measured-wait timings; callback
rates and surface counts; optimized builds; and Metal resize presentation
synchronized with the window transaction. Text resize benchmarks and cache tests
cover repeated preparation work. These changes were made across earlier steps,
not as a separate chronological phase.

## [ DONE ] Supporting scaffold: Render capture and scripted input

Deterministic offscreen rendering to PNG through the production Metal and GLES
renderers, with explicit sizes, display scales, times, and input snapshots.
Multi-frame scenarios exercise hover, focus, scrolling, modals, editing, local
layout, widgets and window-owned resources. Linux capture uses surfaceless EGL.
Demo10–16 and the file manager provide capture scenarios; native checks cover
input delivery and window lifecycle separately. `scripts/check.sh` runs shared
tests, captures and optimized builds; `check-linux.sh` delegates to it.

This captures UI content, not native title bars or desktop composition. Native
window behavior needs separate checks; main/key status alone does not prove a
title bar's visual appearance. See [core/CAPTURE.md](../core/CAPTURE.md).

## Implementation sequence and current priorities

The interactive foundation in 12–22 is implemented. Since the previous roadmap
update, this includes typed retained state, accumulated mouse transitions,
native text/clipboard/IME adapters, single-line editing, custom drag regions,
and localized content-sized layout. Explicit font stacks complete part of 23;
the file manager demonstrates the fixed-height portion of 24. New completed
work in 32–37 covers worker-backed assets, the file manager, GPU shadows,
standard widgets, composed overlays and the original icon font.

Proposed next order:

1. **23 — System font discovery and automatic fallback.** Explicit stacks and
   local tofu already work; find suitable installed faces without application
   configuration or per-frame catalog scans.
2. **25 — Redraw scheduling.** Stop continuous idle updates, including explicit
   wakeups for worker completions, animations, caret blink and timed overlays.
   Any invalidation still updates the main window and all panels together.
3. **31 — Accessibility.** Establish semantics for the now-existing standard
   controls before extending the widget collection substantially.
4. **24 — Reusable virtual lists.** Extract the proven file-manager approach,
   with an explicit offscreen focus/state policy. Variable heights can follow.
5. **38 — Editing refinements and multiline editing**, driven by a concrete app.

Window controls (39), host rendering (26), video (27), and additional platforms
(28–30) can move earlier when an application needs them. Native filesystem
notifications, richer image formats and cache budgets are extensions of 32,
not unfinished requirements of its first implementation.

Selective macOS panel keyboard focus remains optional. Ordinary panel clicks
currently take keyboard focus. This is acceptable: a key panel can leave the
workspace main while its title-bar buttons turn gray. Do not force an active
appearance or prevent panels from becoming key.

### Validation boundaries

- macOS captures/native checks and user feedback establish the existing layout,
  scrolling, panels, editing/IME and widget behavior. Recent widget tests cover
  compound controls, keyboard navigation, overlay dismissal, icon rendering and
  local button sizing; the tab-corner change also has a rendered capture.
- The Omarchy agent recorded passing GLES capture, shared core/editor tests,
  native main/panel lifecycle, keyboard delivery and clipboard checks. This
  supersedes earlier roadmap statements that Linux capture, native panel
  parenting, text input and drag regions were unimplemented.
- Live Wayland IME candidate placement and multi-output scaling still need
  manual verification. Protocol callback tests do not establish live IME UX.
- The subsequent GPU shadow/outline and widget/icon work has Metal evidence;
  its GLES implementation and shared tests still need an Omarchy runtime pass.
  Linux implementation and verification remain delegated to the Omarchy agent.

For new shared API changes, preserve both backend contracts and record checks
that have not actually run. Use focused integration tests and runnable examples,
build with `-o:speed`, check warm allocation reuse, and compare timings against
relevant baselines rather than setting machine-specific limits.

## [ DONE ] Milestone 12: Main window and auxiliary panels

Implemented in demo12:

- One application event loop, explicit `create_window`/`create_panel` lifetimes,
  and generational handles with deferred creation and destruction.
- One main window owns application lifetime. Closing a panel leaves the app
  running; closing the main window closes every panel, including pending ones.
- Panels default to no decorations and do not require an anchor. Initial size
  is supplied by the caller; later OS/user resizing remains authoritative.
- All builders update together: input/dimensions are snapshotted first, then the
  main builder and panel builders run in creation order with the same time.
  Hidden/minimized participants still build; presentation can be skipped.
- Independent frame, input, identity, text/image resource and renderer stores.
  Handles for fonts/images remain local to the owning window or panel.
- The single-window convenience entry point remains available.
- macOS uses floating NSPanel instances, disallows native tabbing for panels,
  hides them when the app deactivates, and preserves the workspace's main role.
  Main status and keyboard/key status are distinct; colored title-bar buttons
  follow key status. Floating behavior has been confirmed manually.
- Wayland uses one application connection/poll loop and independent per-window
  EGL contexts. Panels set their main toplevel as native parent; compositor
  policy controls decoration, stacking, placement and activation.

Native lifecycle/resource checks have been run on both hosts; macOS additionally
checks floating stacking and main/key roles. Omarchy checks cover synchronized
builders and input isolation. See [core/WINDOWS.md](../core/WINDOWS.md).
Minimization/restoration and screen placement remain separate work in 39.

## [ DONE ] Milestone 13: Rich input snapshots

Both backends expose physical keys, pressed/released/held sets, modifiers,
locks, repeat, press-time modifiers and accumulated wheel/trackpad deltas.
Native mouse transitions now accumulate between updates, including a press and
release within one interval. Bits indicate that a transition occurred; they are
not a lossless ordered list of every repeated mouse/key transition.

Reads remain non-consuming and independent of UI focus/hover. Focus/device loss
cancels held interactions without producing an activation. Pointer movement and
release can continue outside bounds during native drag delivery. Text remains
separate from physical keys. Demo11 inspects snapshots; demo12 checks isolation;
demo14 uses them for dragging. Native macOS and Omarchy checks exercise these
paths. Text operations requiring order are covered by 20.

## [ DONE ] Milestone 14: General retained component state

`ui.state(T, init, cleanup, id)` associates a typed payload with the current or
explicit live identity. Payload addresses remain stable when identity storage
grows. Initialization runs on first access; cleanup runs once on disappearance
or window teardown. Type and callbacks stay fixed for the record's lifetime.
Warm access reuses allocations; UI-independent durable data stays application-owned.

Demo14 retains independent drag offsets under explicit keys. Cards share a
coordinate space: reversing declaration order changes overlap order without
moving them. Removal discards identity-owned state. Tests cover growth,
reordering, cleanup and warm reuse. See [core/IDENTITY.md](../core/IDENTITY.md).

## [ DONE ] Milestone 15: Ordered layers and resolved hover

Implemented and covered by core/capture checks. Latest input resolves against
the previous frame's geometry at update start; ordered layer buckets preserve
surface declaration order. Native window occlusion is handled separately by the
platform. See [core/INTERACTION.md](../core/INTERACTION.md).

- Record eligible hit regions, logical ancestry, effective layer/z-order, and
  declaration order. Separate hit-test participation from focusability.
- Resolve the latest input at frame start against the previous completed
  interaction geometry, avoiding an extra frame of stale pointer coordinates.
- Choose the topmost z-order, then deepest eligible node. Define declaration
  order as the final tie-breaker, and verify rendering and hit order agree.
- Expose direct hover and inherited ancestor hover; ancestor regions must also
  contain the pointer. Store assigned/registered hit bounds, not exhausted cuts.
- Start with ordered layer buckets and stable order within a layer. Do not use
  a depth buffer as a replacement for translucent surface ordering.

**Done when:** overlapping regions, nested regions, and reordered siblings have
predictable direct/inherited hover matching their displayed stacking. Include
noninteractive paint and document behavior for newly appearing/moving regions.

## [ DONE ] Milestone 16: Focus and keyboard traversal

Implemented: direct/ancestor focus, click focus, Tab/Shift-Tab traversal, nested
fences, restoration and focused-item scroll reveal. Removed/ineligible focus
clears, or falls back within an active fence. Logical UI focus is retained across
native keyboard-focus loss. Native macOS key routing is tested separately.

- Add one directly focused identity per window, ancestor focus queries, explicit
  focus requests, and focusable-node registration.
- Support click focus and Tab/Shift-Tab traversal in logical tree order. Define
  which focusable ancestor receives a click on a non-focusable descendant.
- Add focus fences restricting traversal to their subtree. Define nested fences,
  focus restoration, and recovery when a focused node disappears.
- Keep native window activation separate from a window's remembered UI focus.
  Focus is queryable state, not permission to read the raw input snapshot.

**Done when:** keyboard navigation and click focus work across nested components
and two windows; ancestor queries are correct; traversal cannot escape a fence;
removing the focused node produces a valid, documented fallback.

## [ DONE ] Milestone 17: Rectangular clipping and content offsets

Implemented in core and both renderer paths, with Metal readback checks at 1x
and 2x and shared GLES capture checks recorded by the Omarchy agent. Multi-output
native scaling remains a separate hardware check.

- Add nested rectangular clip scopes and translation scopes for content.
- Apply intersected clips consistently to solid surfaces, images, text, and hit
  regions. Define logical-to-physical rounding at different display scales.
- Keep clipping out of text layout and avoid adding radius inheritance to cuts.
  Rounded/path clips can be a later extension.

**Done when:** translated text/images are clipped identically on Metal and GLES;
invisible regions do not hover; nested/empty clips and resized/scaled windows
behave correctly without changing text measurements.

## [ DONE ] Milestone 18: Scrollable containers

Implemented using dedicated identity-owned scroll state; general typed state
(14) is not required. Nested delta chaining, clamping, programmatic scrolling,
focus reveal and cleanup have core/capture coverage. Native macOS wheel behavior
has also been confirmed by Hasen; native Wayland delivery is implemented.

- Combine viewport clips, content offsets, retained scroll position, and known
  content extents. Support horizontal and vertical scrolling and clamp offsets
  when content or the viewport changes size.
- Define nested-scroll handling, including which container responds and what
  happens to unused delta at an edge, without consuming the raw input snapshot.
- Provide programmatic scrolling/reveal. Scrollbar widgets and virtualization
  are not prerequisites for this milestone.

**Done when:** nested scroll areas work with a mouse wheel and trackpad; a
scrolled item is hit at its displayed position; content/viewport resizing keeps
offsets valid; scrolling one window does not change another.

## [ DONE ] Milestone 19: Overlays, modal scopes, and custom drag regions

Layer scopes can escape ancestor clips while retaining logical identity ancestry.
Modal scopes combine a pointer/scroll barrier with a focus fence and restore
focus on dismissal. Core and widget scenarios cover nested focus restoration,
Escape/outside dismissal and preventing click-through. Removing scopes removes
their interaction registration. Demo10 exercises the foundations; demo16 adds
menus, nested submenus, popovers and dialogs (36).

`set_window_drag_region` publishes a resolved content-local region for native
window movement on macOS and Wayland. Interactive controls can remain outside
that region. Wayland uses the press serial for `xdg_toplevel.move`, subject to
compositor policy. This replaces whole-background dragging where an app needs
custom chrome; the file manager uses a designated address area.

## [ DONE ] Milestone 20: Text input, clipboard, and composition

Ordered committed-text/composition/edit-command operations are separate from
physical keys and targeted at a window-local identity. Core publishes surrounding
text, UTF-8 selection/marked ranges and caret bounds through shared data. Native
adapters copy what they need; callbacks never run the UI builder. Handled-key
flags prevent duplicate interpretation of IME-owned keys.

macOS implements NSTextInputClient, native range conversion, candidate placement
and clipboard services. Wayland implements XKB typing/dead keys/repeat,
text-input-v3 composition when available, and native data-device clipboard.
Capability queries distinguish typing, composition protocol and clipboard;
protocol support alone does not supply an installed input method.

Native/capture checks cover commit ordering, stale targets, focus changes,
composition cancellation and clipboard routing. Hasen confirmed live macOS IME.
Omarchy native typing and clipboard checks passed; live Wayland candidate
placement remains unverified. Selective panel keyboard focus and richer native
character-range geometry remain optional follow-ups. See
[core/TEXT_EDITING.md](../core/TEXT_EDITING.md).

## [ DONE ] Milestone 21: Single-line text-editing primitives

`core/edit` owns platform-independent buffer operations, grapheme movement and
deletion, selection, composition and undo/redo. Core supplies shaped caret spans,
visual bidi movement, hit testing, selection geometry, drawing and clipped caret
reveal. `edit_text` assembles these for a resolved rectangle; appearance and
buffer ownership remain caller-controlled. Explicit font stacks work throughout
rendering and editing, and unsupported characters produce local tofu.

Demo15 and integration tests exercise combining marks, Arabic/Latin text,
pointer/keyboard selection, composition, clipboard and focus changes. The
standard text/search/number fields now build on these primitives (35).
Current limits: single-line only, whitespace-delimited word commands, bounded
whole-buffer undo snapshots, no typing coalescence, and approximate ligature
caret subdivision. Pasted line breaks/tabs become spaces. Extensions are in 38.

## Extensions and later milestones

Numbers below are retained from the original roadmap; they are not a required
execution order. Some extensions are already complete. The priority list above
identifies proposed next work, subject to application needs.

## [ DONE ] Milestone 22: Local content-sized layout

`open_layout`/`close_layout` resolve a bounded local row/column tree, then consume
a strip from rect cutting. Application code runs once; subsequent passes visit
linear recorded data for measurement and placement. Boxes enter the same
identity tree immediately, retaining state and access to previous-frame
hover/focus/clicks. Deferred paint/text/icon commands use the final geometry.

Roots inherit maximum width and height. Children determine natural size; fixed
sizes, padding, gaps, cross-axis alignment and stretching are supported. There
is deliberately no main-axis Fill, growth weight, proportional shrink or automatic
row wrapping. Overflow uses explicit clipping/scrolling. Demo13 demonstrates a
menu with stretched rows and independently cut toolbar groups. Tests cover
constraints, interaction bounds, single builder execution and storage reuse.
See [core/LAYOUT.md](../core/LAYOUT.md).

## [ PARTIAL ] Milestone 23: System fonts and fallback

Implemented: immutable named explicit font stacks, cached per-face cmap coverage,
script-run/grapheme-aware face selection, consistent baselines and physical face
references throughout shaping, wrapping, measurement, caret geometry and editing.
Uncovered characters render local `.notdef`/tofu instead of replacing the whole
text block with an error. Unchanged frames reuse resolved results.

Remaining:

- Discover configured platform font directories and index minimal face/style
  metadata and Unicode coverage without loading/rasterizing every face eagerly.
- Resolve names and choose fallback outside the explicit stack, loading candidate
  faces lazily. Preserve whole shaping contexts where possible; coverage alone
  is not proof that a font shapes a script or emoji sequence correctly.
- Cache successful and failed choices; version the catalog so changes invalidate
  stale misses. Never scan installed fonts each frame.

**Done when:** an app specifying its preferred font can display mixed-script text
and edit it using suitable installed fallbacks, with correct measurement and
bounded warm-frame work. Color emoji and advanced variation-sequence preferences
are separate extensions. See [core/text/README.md](../core/text/README.md).

## [ PARTIAL ] Milestone 24: Virtual lists

Implemented in the file manager: fixed-height visible-range construction plus
at most five offscreen keyboard targets, full content extents, reveal, and
Tab/Shift-Tab navigation. Capture checks exercise 20,000 entries; warm per-frame
row work is bounded by the viewport rather than directory size. Refresh clears
focus to prevent a reused index from activating another file. Durable selection
and data live outside disappearing row state.

Remaining: expose a reusable core/widget mechanism with explicit stable item
keys, insertion/reorder behavior, and a documented offscreen focus/editing/state
policy. Identity-owned state currently disappears with an omitted row; a generic
list must not silently imply persistence. The file-manager policy is a working
example, not yet a general solution for editable virtualized content.

**Done when:** a second application can use the shared API without duplicating
range/navigation logic, and tests cover focus and durable item state across
scrolling, insertion and reordering. Variable-height caches and scroll anchoring
can follow the fixed-height API as a separate extension.

## [ LATER ] Milestone 25: Redraw scheduling

Request frames for input, geometry changes, application changes, and active
animations. Stop continuous idle redraw. An invalidation from any participant
schedules one application update cycle for the main window and all panels,
matching the current synchronized builder model. Native presentation may still
be paced independently according to visibility and compositor readiness. Give
external producers a way to request presentation when a new frame is available.
Worker file/image completions, animation deadlines, caret blink and tooltip/toast
timers must wake the application without retaining a periodic idle polling loop.

**Done when:** idle windows stop generating regular frames while hover fades,
resizing, scrolling, and explicit invalidation remain responsive. Measure idle
work and interactive latency as well as per-frame execution time.

## [ LATER ] Milestone 26: Host rendering and external GPU images

Separate UI construction, renderer execution, and native window ownership.
Define compatible native-device/target integration points without exposing one
graphics API as a core requirement. Support three concrete paths:

- Paint an externally rendered image inside a rect or as the background.
- Render UI into a transparent texture for a host engine to composite or use
  on a 3D surface.
- Render a HUD directly into a host's existing target, preserving its contents.

Define ownership, resizing, pixel format, color/alpha interpretation, resource
lifetime, and producer/consumer GPU synchronization. Cross-process and cross-API
sharing can follow same-process integration; avoid CPU pixel readback/upload.

**Done when:** a host-driven rendering example exercises all three paths, resizes
targets safely, and runs without our library owning its window or event loop.
Begin with Metal integration, preserving a backend-neutral contract for GLES
and other graphics APIs.

## [ LATER ] Milestone 27: Video as an external image producer

Build on 26. Start on macOS with AVPlayer/AVPlayerItemVideoOutput and compatible
CVPixelBuffer/IOSurface-to-Metal textures. Keep playback timing independent of UI
rebuilds, reuse a frame when no newer one is due, and retain buffers through GPU
completion. Handle audio synchronization, seeking, color conversion and the
possibility of software decode; do not promise zero CPU use. Start with SDR;
HDR and additional platform playback backends are later extensions.

**Done when:** video plays inside a clipped UI region with overlays, pauses and
seeks correctly, and shares frames with the renderer without an application-side
full-frame CPU upload on every update.

## [ LATER ] Milestone 28: Windows desktop backend

Implement native windows, rendering, multiple-window lifecycle, input, focus,
clipboard/composition, scaling and presentation behind the common interfaces.
Choose the graphics backend explicitly rather than assuming the platform and
renderer must be permanently paired. Document capability differences.

**Done when:** shared examples and the interaction/editing integration checks run
on Windows, including multiple windows and display-scale changes.

## [ LATER ] Milestone 29: iOS host-view integration

Add an application/view lifecycle adapter, Metal rendering, touch/pointer input,
software-keyboard/composition integration, display scaling and safe-area data.
Handle background/foreground transitions. Desktop title bars, movable windows,
and ownership of the host event loop must not be core requirements.

**Done when:** a host iOS application embeds the UI, edits text, scrolls by touch,
and survives rotation, keyboard appearance and application suspension/resume.
Define the portable touch representation before implementing this adapter.

## [ LATER ] Milestone 30: Android host-view integration

Reuse the host lifecycle/input contracts from 29 with Android-specific surface,
graphics, touch, keyboard/composition and clipboard support. Choose the renderer
backend and handle surface loss/recreation and density changes explicitly.

**Done when:** the corresponding host example supports touch scrolling and text
editing, and survives surface recreation and background/foreground transitions.

## [ LATER ] Milestone 31: Accessibility semantics and platform adapters

Allow components to declare semantic roles, names, values, actions, and bounds
under stable identities. Integrate semantic focus with keyboard focus, clipping,
scrolling and virtualized content; bridge the data to native accessibility APIs.
Bring this work forward when building a user-facing application rather than
treating it as something to retrofit after a widget API is fixed.

**Done when:** a screen reader can navigate a small example, announce and edit
values, invoke actions, and follow focus/scroll changes through a native adapter.
Add and verify adapters per platform rather than claiming one covers all targets.

## [ DONE ] Milestone 32: Asynchronous files, watched directories and images

`core/files` provides worker-owned I/O with None / Reading / Done state,
revisioned results, cancellation and explicit ownership transfer. Directory
reading/sorting and PNG/JPEG reading/decoding/thumbnail reduction run off-thread.
Watching uses portable metadata polling at roughly 250 ms, not native file events.

`image_file`/`paint_image` accept a path and reuse a per-window bounded cache.
Completed pixels upload on the renderer thread; the last successful image stays
visible during reload or failure. Generational handles protect replaced resources.
Tests cover loading, watch/reload, failure/recovery, cleanup and cache behavior.
Demos use file paths for images except demo3's embedded cursor robot.

Follow-ups: native change notifications if needed, child-metadata refresh for
directory listings, byte-based cache budgets, more image formats and explicit
pinning. Worker wakeups belong to 25. See [core/IMAGES.md](../core/IMAGES.md) and
[core/files/README.md](../core/files/README.md).

## [ DONE ] Milestone 33: File-manager application, first version

`apps/file-manager` is a read-only browser with directory navigation, virtualized
rows, asynchronous watched listings and image thumbnails. Type-to-select accepts
native committed text/IME, selects a matching filename prefix and reveals it;
timeout, repeated-letter cycling, Backspace and Escape have defined behavior.
Searching happens when the prefix changes, not on unchanged frames.

The compact dark design uses custom address-bar chrome with an integrated Close
button and responsive metadata columns; captures cover small tiled window sizes.
Navigation, 20,000-row virtualization, watched updates and type-to-select have
integration coverage. Hasen confirmed the compact design in Omarchy. Examples
were renamed demoN; the application lives separately under apps/.

Opening files, mutations, full-size previews and richer search are future app
features, not requirements of this completed first version. See
[apps/file-manager/README.md](../apps/file-manager/README.md).

## [ DONE ] Milestone 34: GPU shadows and hollow outlines

Metal and GLES shaders render rounded-rectangle outer shadows and inward
antialiased outlines. Shadows use analytic integration plus fixed sampling for
rounded corners; no CPU rasterization, cached blur image or extra blur pass is
needed. They are paint surfaces, independent of layout and hit bounds, and obey
clips/layers. Outlines also work in local layout; shadows need resolved geometry.

Metal readback checks cover visible pixels, alpha, clipping and scaling. The
new GLES path still needs an Omarchy runtime check. Arbitrary silhouettes, inset
shadows and subtree/backdrop blur are outside this milestone. See
[core/SHADOWS.md](../core/SHADOWS.md).

## [ DONE ] Milestone 35: Standard controls and dark theme

A `widgets` package imports core; core does not import widgets. Plain theme data
configures appearance, caller data owns application values, and identities retain
transient interaction state. Demo16 is the responsive control gallery.

Implemented: buttons, checkbox/mixed state, radio groups, animated toggles,
text/search/number fields, sliders, progress, badges, labels, separators, tabs,
segmented controls, list items and a draggable scrollbar. Disabled, hover,
pressed, selected and keyboard-focus states remain distinct. Compound controls
use continuous borders and focus geometry; ordinary tabs have rounded top and
square bottom corners where their outline meets the selected underline.

Buttons default to supplied fixed geometry and fitted labels. The same button
API supports explicit content sizing or fixed dimensions within local layout,
plus icons or icon-only content; no separate content-button widget is needed.
Other controls currently require resolved geometry. Integration tests cover
pointer cancellation, keyboard activation/navigation, editing and local sizing.
See [widgets/README.md](../widgets/README.md).

## [ DONE ] Milestone 36: Panels, menus and overlay widgets

Composed widgets provide in-window panels/inspectors, disclosures/trees/accordions,
menus and submenus, context menus, dropdowns, popovers, dialogs, tooltips and
toasts. These panels are UI containers, distinct from native auxiliary windows.

Menus clamp/flip, scroll, support keyboard navigation and use shadowed layers
outside ancestor clips. Modal barriers, focus fences, restoration and topmost
Escape/outside dismissal prevent click-through. Dialogs have explicit interior
padding and an optional bottom action area with divider. Tooltip delay and toast
lifetime use frame time. Submenus currently open explicitly, not on hover delay.

Demo16 captures and scripted interactions cover these behaviors, including
nested dismissal, compound triggers and unclipped focus outlines. Hasen confirmed
the menu, dialog and field spacing fixes. New widget/GLES validation remains a
Linux-host follow-up; native panel lifetimes belong to 12.

## [ DONE ] Milestone 37: Icon glyphs and a compact default font

`Icon_Glyph` identifies a physical font and resolved glyph. Generic draw and
local-layout APIs share the glyph atlas, fit ink within the requested box and
emit one textured surface on a warm draw without text shaping. Buttons can mix
icons and text or show an icon alone.

The original ten-icon default font is 2,332 bytes, with editable SVG sources,
stable private-use code points and a reproducible generator. Codes resolve to
glyph IDs at load time; indices are not public constants. Normal builds use the
checked-in font and need no generator dependencies. Alternative packages can
supply the same primitive or replace the widget semantic set. Resources remain
window-owned. Capture/readback checks cover antialiasing, scale and button use.
See [icons/default/README.md](../icons/default/README.md).

## [ LATER ] Milestone 38: Editing refinements and multiline text

Extend 21 around an actual editor use case. First improve Unicode word boundaries,
typing undo coalescence and ligature caret positioning without regressing bidi,
font fallback or composition. Then add multiline/wrapped editing, vertical caret
movement with a remembered horizontal goal, line-aware selection/hit geometry,
and scrolling/reveal using the same text layout results as drawing.

**Done when:** a multiline example supports wrapped mixed-script text, selection,
clipboard, undo/redo and IME through resizing and scrolling, with cached unchanged
geometry and explicit large-document limits. Keep single-line field semantics
and APIs intact; do not turn this into a document engine by default.

## [ LATER ] Milestone 39: Native window controls and placement

Add minimize/restore/show/hide and screen/work-area information with explicit
backend capabilities. Support an application temporarily minimizing its main
window, showing a transparent undecorated auxiliary surface, then restoring the
workspace. Do not conflate OS minimization with skipping UI construction.

**Done when:** a focused example exercises that lifecycle and restoration without
breaking the main-window ownership or synchronized-update rules. Respect Wayland
restrictions on global positioning/activation rather than promising identical
behavior across desktops. Screen capture/OCR is a possible application, not part
of this window-control milestone.
