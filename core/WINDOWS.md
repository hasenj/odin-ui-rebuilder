# Main window and panels

The main window owns application lifetime. Panels are auxiliary UI: closing a
panel leaves the application running; closing the main window closes every panel
and returns from the application loop.

```odin
ui.init()
defer ui.shutdown()

main := ui.create_window("Workspace", 960, 640, draw_workspace)
panel := ui.create_panel("Tools", 400, 300, draw_tools)
ui.run() // Returns when the main window closes, even if panels remain open.
```

Create one main window per `init`/`shutdown` session. `ui.open_window(...)` remains
the convenience form; its builder can call `create_panel` too. Panels default to
`decorated = false`; opt into decorations when appropriate. On macOS, panels
never become native tabs. Transparency retains the existing platform defaults
(on for macOS, off for Linux) and can be selected explicitly.

Dimensions specify initial content size in logical points. OS resizing determines
later sizes. Panels do not require anchors. Screen placement, minimization and
restoration APIs are separate future work.

## One application update cycle

A single application timer targets 60 cycles per second. Each cycle:

1. Applies queued lifetime changes and freezes the participating windows.
2. Snapshots input and dimensions for **all** participants before any UI builder.
3. Runs the main builder, then panel builders in creation order.
4. Presents their output where native surfaces are available.
5. Applies creation/closure requests after the cycle finishes.

Every builder receives the same `current_frame().time`, measured from application
initialization. Hidden, minimized and occluded participants still build UI. Native
presentation callbacks never independently run builders. On macOS, live-resize
notifications can request an additional whole-application cycle; reentrant
requests during a cycle are ignored because that cycle is already in progress.

Builder order is sequential, not transactional: shared application data changed
by an earlier builder is visible to later ones. Changes from a panel reach the
main builder on the next cycle. Input arriving during a cycle also belongs to
the next snapshot, regardless of which builder is currently executing.

This is still continuous updating, not an on-demand invalidation API. The common
cycle entry point is the foundation for adding that later.

Frame timing remains per participant. `frame wall` sums that participant's
snapshot, build and presentation durations, excluding time spent in other
builders; all participants' callback rates describe application cycles. A hidden
participant may have update time with no presentation time.

## Lifetime and handles

`ui.Window` and its alias `ui.Panel` are generational handles; zero is invalid.
`ui.window_alive` / `ui.panel_alive` accept pending creations as alive and report
false immediately after a close request. Stale handles cannot target replacements,
including across shutdown/reinitialization.

`ui.close_panel(handle)` is idempotent and ignores stale or main-window handles.
`ui.request_close(handle)` also works for either role; closing the main window
requests application shutdown. Native close buttons follow the same path.
Command-Q on macOS closes the main window and panels through orderly cleanup.

Requests made inside a builder take effect at the cycle boundary. All participants
captured at the start still complete that cycle, even if another builder requests
their closure. A newly created panel first participates in the next cycle.
Resource destruction happens after presentation, never inside a builder.

Main-window closure also cancels pending panels. Once the main window is closing,
`create_panel` returns zero. Panels cannot replace the main window or keep the
application alive. `shutdown` can discard pending creations without showing them.

All lifecycle APIs run on the main thread. Call `init`, `run` and `shutdown`
outside UI updates. Builders may create/close panels or request main-window closure.

## State and resources

During each builder, `ui.current_window()` / `ui.current_frame().window` identifies
the current main window or panel. Its implicit UI context owns input, rect stacks,
identities, animation, focus, scrolling, text caches, glyph atlases and images.
Shared update scheduling does not merge those stores.

Font, image and identity handles are **local to their window/panel**. Do not share
them with another participant or a reopened replacement. Font aliases simplify
loading in whichever context is current:

```odin
if _, found := ui.find_font("UI"); !found {
    _, err := ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf", "UI")
    assert(err == .None)
}
ui.text("Hello", "UI")
```

Application globals remain shared application data; creating a panel does not
clone them. General typed retained component state is still future work.
Headless captures remain independent sessions with a zero window handle and
caller-supplied frame times.

## Backends and checks

macOS uses NSWindow for the main window and NSPanel for panels, each with its own
Metal renderer. MetalKit's independent update timers are paused. The application
timer snapshots/builds all participants and explicitly draws visible output.
Panels float above the workspace while the app is active and hide when another
app becomes active. A panel can become the native key window (keyboard input)
while the workspace retains main-window status. Title-bar buttons reflect key
status: the workspace buttons turn gray while a panel has keyboard focus.
Panels never become the main window. Mouse hit
testing checks the native window under the pointer, so overlapping panels block
hover beneath them.

Wayland uses one poll loop and one application connection, with an independent
EGL context for each window. Panels identify the main toplevel as their parent. Application
update deadlines are independent of compositor frame callbacks. A compositor
callback permits presentation of a surface; waiting for it never stops UI builds
in that or another window. Panels use ordinary xdg-toplevel surfaces with framework
lifetime semantics and a preference for no decorations. The compositor may
override decoration requests.

```sh
./scripts/build.sh demo12
./bin/demo12
./scripts/check-windows.sh
```

Demo12 opens a workspace and borderless inspector panel. The main window opens or
reopens the panel; the panel can increment shared application data or close itself.
Closing the main window ends both. Both display the same application update clock.

The native lifecycle check covers synchronized builder counts/timestamps/order,
state/resource isolation, deferred creation/closure, slot reuse, stale handles,
main-window shutdown with live/pending panels, and reinitialization. macOS checks
also verify native key routing, input snapshot boundaries, tabbing/decoration
policy, main/key focus roles, floating-panel stacking, hidden-panel updates, resize,
close/quit, and extra draw callbacks.

On macOS and Linux, `./bin/demo12 --capture` saves both views to `bin/demo12-0.png` and
`bin/demo12-1.png`. Linux runtime checks require a graphical Wayland session;
cross-compilation alone does not verify compositor behavior.
