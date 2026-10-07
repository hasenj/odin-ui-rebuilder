Maintained by Codex (the AI assistant).

Updated by Codex on 2026-10-08.

# Roadmap

An Odin UI framework that reconstructs its UI on each update:

    Application Data -> UI Structure -> Rendering Primitives -> Screen Pixels

The same paradigm was explored in go.hasen.dev/shirei. Rect cutting and local
layout share immediate-mode input and retained identities.

This file tracks scope, status and priority. [IDEAS.md](IDEAS.md) owns future
design details and acceptance criteria; package docs describe implemented APIs.
Milestone numbers are stable work-package IDs, not demo numbers or execution order.
DONE means the stated scope is implemented, subject to the verification notes below.

## Proposed next order

25 (redraw scheduling) → 31 (accessibility) →
38 (editing extensions).

Other work can move forward when an application needs it.

## Milestones

| # | Status | Milestone | Scope / remaining work |
| --- | --- | --- | --- |
| 0 | DONE | Basic structure | Odin packages and general platform interface. |
| 1 | DONE | Rendering primitives | GPU surfaces, rounded corners, alpha and batching. |
| 2 | DONE | Input as data | Pointer position and held buttons; extended in 13. |
| 3 | DONE | [Images](../core/IMAGES.md) | PNG/JPEG, generational handles and size queries. |
| 4 | DONE | [Linux / Wayland](../platform/LINUX.md) | Native windows and EGL/GLES rendering. |
| 5 | DONE | [Rect cutting](../core/RECT_CUTTING.md) | Resolved cuts, padding and immediate painting. |
| 6 | DONE | [Font loading and Latin text](../core/TEXT.md) | FreeType/HarfBuzz, variable fonts, atlases and caches. |
| 7 | DONE | Arabic and bidi | SheenBidi analysis and mixed-script shaping. |
| 8 | DONE | Wrapped and fitted text | Width/height constraints and reusable paragraph preparation. |
| 9 | DONE | [Identities and animation](../core/IDENTITY.md) | Scoped keys, retained hover animation and generational IDs. |
| 10 | DONE | Transparent windows | Transparency and decoration options on both backends. |
| 11 | DONE | Frame instrumentation | Wall/update/submit/wait timings and resize fixes. |
| 12 | DONE | [Main window and panels](../core/WINDOWS.md) | Shared update cycles, isolated resources and native parent relationships. |
| 13 | DONE | Rich input snapshots | Keys, modifiers, repeat, scrolling and accumulated mouse transitions. |
| 14 | DONE | [Typed retained state](../core/IDENTITY.md#typed-component-state) | Stable payloads, initialization and cleanup. |
| 15 | DONE | [Layers and resolved hover](../core/INTERACTION.md) | Ordered painting and previous-frame interaction geometry. |
| 16 | DONE | Focus and traversal | Click/Tab focus, ancestor queries, fences and restoration. |
| 17 | DONE | Rectangular clipping | Nested clips and translated content, including hit bounds. |
| 18 | DONE | Scroll containers | Nested scrolling, clamping, reveal and retained offsets. |
| 19 | DONE | Overlay foundations and drag regions | Modal barriers, clip escape and custom native window dragging. |
| 20 | DONE | [Native text input](../core/TEXT_EDITING.md) | Text operations, clipboard and composition adapters. |
| 21 | DONE | Single-line editing | Graphemes, bidi caret/selection, IME and undo/redo. |
| 22 | DONE | [Local content-sized layout](../core/LAYOUT.md) | Bounded rows/columns and cross-axis stretch; no main-axis flex growth. |
| 23 | DONE | [System fonts and fallback](../core/TEXT.md#system-font-catalog) | Directory/cmap catalog, lazy named faces and cached automatic fallback; explicit startup scan. |
| 24 | DONE | [Virtual lists](../core/VIRTUAL_LIST.md) | Shared fixed-height keyed lists, bounded focus targets, reveal and explicit offscreen state policy. |
| 25 | LATER | [Redraw scheduling](IDEAS.md#redraw-scheduling-25) | Idle without regular frames; wake for changes and timed work. |
| 26 | LATER | [Host rendering and external GPU images](IDEAS.md#external-gpu-content-and-engine-integration-26) | External textures, UI textures and direct host-target HUD rendering. |
| 27 | LATER | [Video](IDEAS.md#video-as-an-external-image-producer-27) | Playback as a GPU image producer; depends on 26. |
| 28 | LATER | [Windows desktop](IDEAS.md#windows-desktop-28) | Native backend and shared example/test coverage. |
| 29 | LATER | [iOS host views](IDEAS.md#ios-host-views-29) | Host lifecycle, Metal, touch and software keyboard. |
| 30 | LATER | [Android host views](IDEAS.md#android-host-views-30) | Reuse mobile contracts; handle Android surface lifecycle. |
| 31 | LATER | [Accessibility](IDEAS.md#accessibility-31) | Semantic data and native adapters. |
| 32 | DONE | [Asynchronous assets](../core/files/README.md) | Worker directory/image loading, metadata polling and path-image caching. |
| 33 | DONE | [File manager, first version](../apps/file-manager/README.md) | Compact read-only browser, thumbnails and type-to-select. |
| 34 | DONE | [GPU shadows and outlines](../core/SHADOWS.md) | Rounded-rectangle outer shadows and hollow borders. |
| 35 | DONE | [Standard controls](../widgets/README.md) | Semantic light/dark schemes, input/navigation controls and explicit button sizing. |
| 36 | DONE | [Panel and overlay widgets](../widgets/README.md#containers-and-overlays) | Menus, dialogs, panels, disclosures, tooltips and toasts. |
| 37 | DONE | [Icon glyphs](../icons/default/README.md) | Generic glyph primitive and original ten-icon default font. |
| 38 | LATER | [Editing extensions](IDEAS.md#editing-extensions-38) | Word/caret/history refinements and multiline editing. |
| 39 | LATER | [Native window controls](IDEAS.md#native-window-controls-and-placement-39) | Minimize/restore/show/hide and screen/work-area information. |

**Completed supporting scaffold:** [render capture and scripted input](../core/CAPTURE.md)
through production Metal/GLES renderers. `scripts/check.sh` runs tests, captures
and optimized builds; `check-linux.sh` delegates to it. Capture does not verify
native desktop composition or actual IME candidate windows.

## Verification still needed

- Omarchy: live IME candidate placement and multi-output scaling.
- Omarchy: the newer shadow/outline, widget and icon work needs a GLES runtime pass.
  Earlier shared capture/editor and native panel/input/clipboard checks were
  recorded as passing by the Omarchy agent.

Linux implementation/verification remains with the Omarchy agent. This roadmap
update does not represent a fresh full test run. Preserve both backend contracts,
use focused integration checks, and measure warm allocation reuse and performance.
