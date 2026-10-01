# Native windows

Window lifetime is explicit. One application loop drives all windows on the main
thread; each window has its own update procedure and UI state.

```odin
ui.init()
defer ui.shutdown()

workspace := ui.create_window("Workspace", 960, 640, draw_workspace)
inspector := ui.create_window("Inspector", 400, 600, draw_inspector)
ui.run() // Returns when the final window closes.
```

`ui.open_window(...)` remains the convenience form for a single window. It now
returns to the caller after that window closes, with its resources released.
The decoration, transparency and frame-timing options work with either form.
Dimensions passed to creation are initial content dimensions in logical points;
subsequent frames use the actual native window size.

## Lifetime and handles

`ui.Window` is a generational handle. Its zero value is invalid. Use
`ui.window_alive(handle)` to check it; pending creations count as alive, and
requested closes immediately count as no longer alive. Old handles cannot refer
to replacements, including across application shutdown/reinitialization.

`ui.request_close(handle)` is idempotent and ignores stale handles. Calling it
inside an update is safe: that update and its submission finish before resources
are released. Native close buttons use the same deferred destruction path.
On macOS, Command-Q closes all windows and returns from `run`, so application
cleanup still runs.

Creating a window inside an update is also safe. Creation is queued; its first
update happens after the current callback finishes. No UI updates are nested.
A newly requested window keeps the loop alive even if the current callback also
closes the last existing window. Initial windows appear when `run` begins.
`shutdown` can also discard pending windows without ever creating native ones.

All lifecycle APIs are main-thread operations. `init`, `run` and `shutdown`
must be called outside updates; callbacks may use `create_window`,
`request_close` and `window_alive`. This is not yet a host-driven event-loop API.

## State and resources

During an update, `ui.current_window()` and `ui.current_frame().window` identify
the window. The implicit builder context switches to that window for the entire
callback. Input, rect stacks, identities, animation, focus, scrolling, text caches,
glyph atlases, images and renderer resources are independent.

Font, image and identity handles are **window-local**. Do not use them in another
window, or retain them for a reopened replacement. For fonts, an easy pattern is
to look up a window-local alias and load it if absent:

```odin
if _, found := ui.find_font("UI"); !found {
    _, err := ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf", "UI")
    assert(err == .None)
}
ui.text("Hello", "UI")
```

Application globals remain application globals; opening a window does not clone
them. Keep application-owned state separately per window when needed. The
framework's general typed retained-state API is still future work.

Headless capture sessions remain independent and report a zero `current_window`.
Their resource handles must not be exchanged with native windows either.

## Backends and checks

macOS uses one NSApplication loop, an NSWindow/MTKView/Metal renderer per window,
and a lifecycle timer that applies pending requests outside render callbacks.
Keyboard responders are window-specific. Mouse hit testing checks the native
window under the pointer, so an overlapping window blocks hover underneath it.

Wayland currently uses a separate connection, EGL context and renderer per
window. A single poll loop handles all connections and switches EGL contexts
before rendering or releasing resources. A hidden window waiting for a compositor
frame callback does not prevent other windows from updating. This deliberately
keeps resources independent; shared GPU assets/connections can be considered later.

```sh
./scripts/build.sh app12
./bin/app12
./scripts/check-windows.sh
```

App12 opens a workspace and inspector with independent scrollable lists and focus.
Each has buttons to open the other window or close itself. Tab traverses buttons;
Enter activates the focused button. Closing both ends the program. Frame timing
logs include the window index and generation.

The native lifecycle check opens two windows, closes and replaces one from update,
checks state/resource isolation, rejects stale handles, opens a successor while
closing the last window, and verifies return/cleanup/reinitialization. On macOS it
also sends a native key event, resizes a window, invokes native close and quit, and
pumps draws explicitly so the test works without display refresh.

On macOS, `./bin/app12 --capture` saves both sample views to `bin/app12-0.png` and
`bin/app12-1.png`. These are deterministic render checks; the native executable
separately checks the lifecycle. Linux runtime checks require a graphical Wayland
session; cross-compilation alone does not verify compositor behavior.
