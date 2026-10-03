This file is maintained by the human programmer (Hasen). Do not edit it unles explicitly requested to.

Milestone expansion below written by Codex at Hasen's explicit request on
2026-09-30. [IDEAS.md](IDEAS.md) contains the supporting future-work discussion.
Milestone numbers identify work packages, not example app numbers. Completed
work after milestone 3 is grouped retrospectively; future ordering is proposed.
Updated by Codex at Hasen's request on 2026-10-02 to reflect implementation
through demo12 and the agreed panel behavior. Numbers remain stable even where
work was completed out of order. DONE describes implemented scope; platform
verification limits are called out separately.

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
as a readable frame snapshot. Keyboard, transitions, and scrolling are later work.

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
both base directions. This does not yet include editable text or font fallback.

## [ DONE ] Milestone 8: Wrapped and fitted text

`layout_text` wraps paragraphs; `layout_text_fit` shrinks a label to a minimum
size, optionally wraps there, and checks width and height limits. Paragraph
preparation is cached independently of width so normal resizing reuses shaping
and bidi analysis. Demo7 demonstrates wrapping, fitting, and centered labels.

## [ DONE ] Milestone 9: Hover, logical identities, and animation

Rect-level hover queries; a retained identity tree using parent, explicit integer
or caller-location key, and per-key occurrence; generational node handles; and
retained float animation. Distinct integer types remain distinct keys. Demo8
demonstrates independently animated hover colors. Overlap-aware hover and focus
are not part of this completed milestone.

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

Deterministic offscreen Metal rendering to PNG, using the production renderer
with explicit sizes, display scales, times, and input snapshots. Multi-frame
scenarios exercise hover, focus, scrolling, modals, and window-owned resources.
Demo10–12 provide capture scenarios; native macOS checks cover input delivery and
window lifecycle. `scripts/check.sh` runs tests and optimized example builds.

This captures UI content, not native title bars or desktop composition. Native
window behavior needs separate checks; main/key status alone does not prove a
title bar's visual appearance. Capture currently requires macOS Metal; other
capture backends return Unsupported. See [core/CAPTURE.md](../core/CAPTURE.md).

## Implementation sequence and current priorities

Implemented since the original roadmap: the main-window/panel lifecycle (12),
keyboard and scroll snapshots (part of 13), layers/hover (15), focus (16), clipping
(17), scrolling (18), and the overlay/modal portion of 19. Demo10 demonstrates the
interaction foundations, demo11 physical keys, and demo12 multiple native surfaces.

Remaining near-term work:

- Complete native panel semantics on Wayland and verify them in Omarchy (12).
- Finish native mouse-transition accumulation and drag/focus-loss coverage (13).
- Add general typed retained state (14), then custom native drag regions (19).
- Proceed to text input/composition (20) and text editing (21).

Selective macOS panel keyboard focus is deferred until text-input work provides
a concrete need. Ordinary panel clicks currently take keyboard focus. This is
acceptable: a key panel can leave the workspace main while its title-bar buttons
turn gray. Do not force an active appearance or prevent panels from becoming key.

Cross-platform validation remains explicit: macOS native and Metal checks run
here; Linux keyboard work was also implemented by the Omarchy agent. New shared
interaction/rendering and multi-window behavior still needs targeted Wayland
runtime verification; compile coverage alone is not that verification.

Milestones 12–21 establish a minimum interactive UI foundation, rather than a
widget collection. Keep macOS and Wayland working through each shared API change.
Use focused integration tests and a runnable example for the new behavior; build
examples with `-o:speed`. Record platform checks that have not actually been run.
For interaction/state work, check allocation reuse after warm-up and compare
timings against a relevant baseline rather than setting a machine-specific limit.

## [ PARTIAL ] Milestone 12: Main window and auxiliary panels

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

Remaining:

- Wayland currently creates independent xdg-toplevels on separate connections.
  Move to a shared application connection and establish panel parenting with
  `xdg_toplevel.set_parent`. Respect compositor control over activation and
  appearance instead of promising identical AppKit behavior.
- Run lifecycle, resize, input isolation and stacking checks in Omarchy.
- Minimization/restoration, screen placement and related native window controls
  remain separate follow-up work, not prerequisites for basic panel lifetime.

**Done when:** the implemented lifecycle and resource-isolation checks also pass
on Wayland, and panels have native parent/auxiliary behavior there. macOS checks
already cover callback-time closure, stale handles, reopening, synchronized
updates, native key routing, floating stacking and main/key roles. See
[core/WINDOWS.md](../core/WINDOWS.md).

## [ PARTIAL ] Milestone 13: Rich input snapshots

Physical keys, pressed/released/held sets, modifiers, locks, repeat, press-time
modifiers and accumulated wheel/trackpad deltas are implemented on both hosts.
Demo11 inspects this data; demo12 exercises per-window isolation. macOS native
checks cover keyboard routing and focus loss; Linux has evdev/XKB input tests.

Remaining: native mouse transitions are currently inferred from sampled held
state, so a press and release between updates can be missed. Accumulate those
transitions explicitly and finish multi-window drag/device-loss checks. The
following requirements still define the complete milestone:

- Add per-window mouse/key pressed, released and held state, keyboard modifiers,
  repeat information, and wheel/trackpad deltas with documented units.
- Accumulate transitions between updates; define how multiple transitions in
  one update interval are represented. Keep reads non-consuming and available
  regardless of UI focus or hover.
- Handle native focus loss and pointer/keyboard device loss without stuck keys
  or drags. Preserve the distinction between physical keys and text input.

**Done when:** an input-inspection example shows quick press/release, held keys,
modifiers, scrolling, and focus loss correctly in each window on both backends.
Text commitment, composition and clipboard integration are deferred to 20.

## [ TODO ] Milestone 14: General retained component state

Depends on the identity system; place after 13 to exercise real input use cases.

- Add typed state associated with identities, with explicit initialization,
  access lifetime, type checking, and cleanup rules.
- Avoid exposing pointers that silently become invalid when storage grows.
  Define cleanup for state that owns allocations or other resources.
- Demonstrate retained values for selection and dragging. Raw pointer state
  remains readable during a drag even when hover is lost; do not require an
  exclusive framework event-dispatch/capture model.

**Done when:** two instances of a component retain independent values through
reordering and animation; removing an identity or closing its window cleans up
its state. Warm stable frames reuse storage without repeated allocation.

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
and 2x. GLES runtime verification remains an explicit Linux-host check.

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

## [ PARTIAL ] Milestone 19: Overlays, modal scopes, and custom drag regions

Layer scopes can escape ancestor clips while retaining logical identity ancestry.
Demo10 opens/closes a modal through buttons, combines a full-window hit barrier
with a focus fence, and restores focus on dismissal. Capture scenarios cover
pointer/scroll blocking, Tab traversal, cancelled clicks and restoration.

Remaining: application-defined native drag regions, plus focused coverage for
nested modal dismissal and owner disappearance. Borderless macOS windows still
use native background dragging; there is no custom drag-region API yet.

- Let an overlay retain logical parentage while drawing in another layer and
  escaping the parent's clip through an explicit API.
- Distinguish passive overlays, focus-taking overlays, and modal input barriers.
  A Tab fence alone does not prevent pointer interaction outside a modal.
- Define dismissal, nested-modal ordering, owner disappearance, and focus
  restoration. Z-order alone must not grant keyboard focus.
- Add application-defined native window drag regions so interactive controls
  can coexist with borderless-window movement. Respect platform restrictions.

**Done when:** a popup from a scrolled region draws and interacts outside its
parent clip; passive overlays do not steal focus; a modal blocks normal outside
interaction and restores focus when closed; a designated title region can move
the window without making every control draggable.

## [ TODO ] Milestone 20: Text input, clipboard, and composition

Depends on 13 and 16–17.

- Expose committed text, composition/preedit state, and clipboard operations as
  data/services separate from physical key input.
- Associate text-input activation and candidate positioning with the focused
  identity and its window; translate caret geometry into native coordinates.
- Revisit selective panel keyboard focus here: mouse-only palette controls may
  leave the workspace key, while text fields request keyboard focus for their
  panel. Keep mouse ownership independent of key-window status if adopting this.
  This refinement was deliberately deferred after checking Acorn's behavior.
- Implement the relevant macOS and Wayland integrations, including explicit
  capability handling where a compositor lacks an optional protocol.

**Done when:** an input probe accepts accented text and IME composition without
duplicate commits, supports paste/copy, positions candidates by the caret, and
handles focus changes between windows and components.

## [ TODO ] Milestone 21: Text-editing primitives

Depends on 14, 16–18, and 20.

- Provide grapheme-aware movement/deletion, selection ranges, caret placement,
  point-to-text hit testing, and selection-to-geometry queries.
- Handle shaped clusters and bidi ordering; define logical versus visual
  movement rather than assuming one character equals one glyph or one rect.
- Integrate clipboard/composition and caret reveal in a clipped scroll region.
  Start with single-line editing; multiline editing can follow separately.

**Done when:** a small editor assembled from these primitives supports keyboard
and pointer selection, combining marks, mixed Arabic/Latin text, composition,
clipboard operations, and focus changes. A general text-field widget API is not
required to demonstrate the building blocks.

## Later milestones — provisional order

These extend the foundation; they are not prerequisites for completing 12–21.
Reorder them around actual application needs. In particular, a new platform or
GPU integration may be brought forward without waiting for every entry above.

## [ LATER ] Milestone 22: Local content-sized layout

Measure a localized row/column component whose children determine its size, then
feed the resolved result into rect cutting. Keep the algorithm self-contained
and separate from the identity tree; avoid replacing the whole layout model.

**Done when:** a component combines text and fixed-size children, resolves its
outer size, and embeds in a cut/scroll region without caller-written duplicate
measurement or a second whole-window layout system.

## [ LATER ] Milestone 23: System fonts and fallback

Discover platform font locations, index minimal metadata/coverage information,
resolve names, and load faces on demand. Add fallback that respects shaping
clusters and scripts rather than substituting isolated missing glyphs blindly.

**Done when:** mixed-script text can use several font files automatically, with
correct measurement, cache invalidation and resource lifetime, without loading
or rasterizing every installed font upfront.

## [ LATER ] Milestone 24: Virtual lists

Start with fixed-height rows: derive the visible range from viewport and scroll
offset, retain the full content extent, and key rows by stable item IDs. Define
how focus/editing survives an offscreen row no longer being declared; do not
silently lose state or apply an old row's state to another item. Variable-height
measurement caches and scroll anchoring are a follow-up extension.

**Done when:** a large list builds work proportional to the visible range, keeps
correct scrolling and row identities through insertion/reordering, and has an
explicit offscreen focus/state policy. Depends on 14, 16, and 18.

## [ LATER ] Milestone 25: Redraw scheduling

Request frames for input, geometry changes, application changes, and active
animations. Stop continuous idle redraw. An invalidation from any participant
schedules one application update cycle for the main window and all panels,
matching the current synchronized builder model. Native presentation may still
be paced independently according to visibility and compositor readiness. Give
external producers a way to request presentation when a new frame is available.

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
