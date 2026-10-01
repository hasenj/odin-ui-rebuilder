# macOS windows

The public window API accepts independent decoration and transparency options:

```odin
ui.open_window("Custom window", 780, 510, update,
    decorated = false, transparent = true)
```

`decorated` defaults to `true`. Set it to `false` to remove the native title bar,
traffic-light buttons and frame. Borderless windows can still become key/main
windows. They support dragging by the window background as a temporary default
until application-defined drag regions exist. The application menu provides
Command-Q to quit, including when there is no native close button.

`transparent` defaults to `true` on macOS. Each frame clears to transparent
black; unpainted areas show the desktop or windows underneath. Painting with
alpha 1 makes a region opaque; intermediate alpha blends with the content behind
the window. Rounded corners leave transparent pixels outside the painted shape.
Transparency is compositing, not a blur/vibrancy effect.

Set `transparent = false` to use the previous opaque dark clear color. The two
options are independent: a decorated window can have transparent content, and a
borderless window can be opaque. Transparent windows disable the native window
shadow so the application controls the visible shapes.

The implementation sets the NSWindow background to clear, marks the window,
Metal view and backing layer nonopaque, and clears the Metal attachment with
zero RGBA. The existing shader and source-over blend pipeline already preserve
premultiplied alpha. Clearing every frame removes old pixels as shapes move.
The native title bar, when enabled, retains its normal macOS appearance.

Visual transparency does not define framework hit testing or a custom OS input
region. `ui.hovered()` continues to test rect geometry. Background dragging is a
window-wide native behavior, not an application input-routing implementation.

Linux keeps its existing decorated/opaque defaults, but supports explicit
`transparent = true`. `decorated = false` requests client-side decorations on
Linux, subject to compositor policy. App9 requests transparency and no system
decorations on both platforms.

## Example and checks

Wheel and trackpad scrolling are delivered through the Metal view's
`scrollWheel:` responder. Precise deltas, including system momentum events,
remain in logical points; coarse deltas use 40 points per line. AppKit applies
the user's natural-scroll preference. Both axes accumulate between frames and
are supplied once in `input.scroll_delta`; idle frames receive zero.
App10 demonstrates native scrolling. `./scripts/check-macos-input.sh` verifies
real NSEvents and their subsequent frame snapshots on the AppKit main thread.

The Metal view is the window's first responder and captures physical keys,
key releases, modifier changes and native repeats as input data. Tab/Shift-Tab
therefore use core's existing focus traversal and modal fence. Press-time
modifiers survive a quick release before the next frame. Losing key-window
status clears held keys and pending presses while retaining logical UI focus.
AppKit virtual keycodes map to US-position names, independent of event characters.
Keypad Enter and Return are distinct. Modifier changes expose left/right sides
using IOKit's device flags; Caps Lock reports a tap and separate toggle state.
F1–F20 are mapped on macOS; delivery of system/media/Fn keys depends on the OS
and keyboard settings. Text entry and IME remain deferred. Command-Q still uses
the application menu. App11 displays the raw key snapshots.

Run `./scripts/build.sh app9` and `./bin/app9` from the repository root. The
example leaves its root, gaps and padding unpainted, draws an opaque rounded
header and a translucent blue panel, and moves an orange circle across empty
space. The circle should leave no trails. Drag a painted area to move the window;
Command-Q quits it.

`./scripts/check-macos-window.sh` builds a standalone main-thread AppKit check
and opens six short-lived windows: decorated/borderless crossed with opaque,
transparent, and default transparency. It checks the actual native style,
key-window eligibility, view/layer opacity, clear color and quit menu. This is
separate from the ordinary test runner because AppKit windows require the main
thread. The existing Metal readback tests cover transparent pixels, rounded
edges, premultiplied blending and clearing away previous frame contents.

Native references: [NSWindow](https://developer.apple.com/documentation/appkit/nswindow),
[borderless style](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/borderless),
and [MTKView](https://developer.apple.com/documentation/metalkit/mtkview/).

## Multiple windows

`ui.init`, `ui.create_window`, `ui.run`, `ui.request_close` and `ui.shutdown`
provide explicit window lifetimes within one AppKit event loop. The final close
returns from `run`; Command-Q requests orderly closure of all windows. The existing
`ui.open_window` convenience API uses the same lifecycle. See
[core/WINDOWS.md](../core/WINDOWS.md) for ownership rules and app12.
