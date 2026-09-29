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
`transparent = true`. `decorated = false` still asserts on Linux.
App9 enables transparency on both platforms; Linux decorations are compositor-managed.

## Example and checks

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
