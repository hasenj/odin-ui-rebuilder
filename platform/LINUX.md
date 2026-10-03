# Linux / Wayland

The Linux backend uses native Wayland (xdg-shell), EGL, and OpenGL ES 3.0.
The implementation and protocol metadata are Odin; shaders are GLSL ES 3.00. No GLFW,
SDL or protocol-generation step is required. The text dependency SheenBidi is
compiled from vendored C source by the build helper.
Core continues to import the general `platform` package. Odin selects `_linux`
and `_darwin` files for the target OS.

Wheel/trackpad input uses wl_pointer v5 axis/frame groups. Axis values are
surface-local logical points, positive towards the content bottom/right; they
are not multiplied by output scale. Discrete wheel notifications describe the
same movement and are not counted again. Completed groups accumulate until the
next update's `input.scroll_delta` snapshot, then reset. Pointer leave or device
loss clears pending movement. Demo10 demonstrates scrollable content.

wl_keyboard v5 supplies physical keys and modifiers. Evdev codes map to keys
named by US keyboard position, independent of layout, Shift and Num Lock. The
system `libxkbcommon` decodes the compositor's keymap for modifier indices,
lock indicators and repeat policy; modifier bit positions are not hard-coded. Key
transitions preserve press-time modifiers and reset each update. Keyboard leave
or device loss clears held keys and cancels pending presses/repeat. Repeat uses
the compositor's rate/delay. Text input and IME are not implemented yet.

## Build and run in Omarchy

Use a recent Odin compiler with `core:image` PNG/JPEG support and `vendor:egl`.
Development cross-checks used `dev-2026-09-nightly`. Run the following from the
repository root inside the VM:

```sh
sudo pacman -S --needed base-devel wayland libglvnd mesa libxkbcommon freetype2 harfbuzz
./scripts/build.sh demo3
./bin/demo3
```

`wayland` supplies the [client, cursor, and EGL-window libraries](https://archlinux.org/packages/extra/x86_64/wayland/files/).
`libglvnd` supplies [libEGL](https://archlinux.org/packages/extra/x86_64/libglvnd/files/),
and [Mesa](https://archlinux.org/packages/extra/x86_64/mesa/) supplies OpenGL drivers.
Wayland client 1.20+ is required for `wl_proxy_marshal_array_flags`.

SheenBidi 3.0.0 is already included in `third_party/SheenBidi`, with its license.
The build scripts use `cc` and `ar` to create
`bin/text-deps/Linux-<architecture>/libsheenbidi.a` and link it statically.
Nothing is downloaded or installed system-wide for SheenBidi. Use
`./scripts/build-text-deps.sh` to build just that dependency. The Odin binding
references the archive directly, so after this one-time build, plain commands
such as `odin run ./examples/demo10 -out:bin/demo10` work without extra linker flags.
Run the dependency script again after vendored sources change; `./scripts/build.sh`
does this automatically.

`pkg-config` (Arch package `pkgconf`) is optional on Linux with libraries in the
default linker paths. If available, the scripts use it to locate HarfBuzz and
FreeType, including custom installations configured through `PKG_CONFIG_PATH`.

Run the application from a terminal in the graphical Wayland session, as your
normal user. `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` must refer to that session;
running it through an unrelated SSH session or with sudo will not set those up.
The demo0–demo6 examples target either platform; demo3 embeds its assets, and demo4
demonstrates nested rect cuts, padding, and painting. demo5 demonstrates Latin
text with HarfBuzz and FreeType, and demo6 adds Arabic/bidi via SheenBidi; see [text API and setup](../core/TEXT.md).

For a VM without working accelerated OpenGL, try Mesa software rendering:

```sh
LIBGL_ALWAYS_SOFTWARE=1 ./bin/demo3
```

Software-rendered timing numbers do not represent GPU-accelerated performance.
The backend requires OpenGL ES 3.0; it does not fall back to X11 or XWayland.

Desktop OpenGL and GLES capabilities can differ on VM drivers. In the Omarchy
ARM64 VM, the Wayland `virgl` driver accepts GLES 3.0 but rejects a desktop
OpenGL 3.3 core context with `EGL_BAD_MATCH`. The renderer uses GLES 3.0 for
instancing, vertex arrays, and its shaders. Odin's `vendor:OpenGL` supplies the
shared function bindings; loading those bindings does not select desktop GL.

## Transparent windows

Pass `transparent = true` to `ui.open_window` to show the desktop or windows
behind unpainted areas. Linux defaults to `false`, preserving the opaque dark
background. Alpha-1 paint stays opaque; translucent paint and rounded edges
blend with the content behind the window. This is alpha compositing, not blur.

The EGL config includes an alpha channel, and each transparent frame clears to
zero RGBA before drawing with premultiplied source-over blending. The Wayland
surface retains its default empty opaque region so the compositor honors alpha.
Clearing every frame removes old shapes without trails. Transparency does not
change the input region: the full window rectangle still receives pointer input.

Run `./scripts/build.sh demo9` and `./bin/demo9` for a demo with unpainted gaps,
rounded panels, translucent paint, and a moving circle. Use compositor shortcuts
to move or close the window. Demo9 also passes `decorated = false`.

`decorated = true` (the default) requests server-side decorations through
`xdg-decoration` when supported. `decorated = false` requests client-side mode;
the library draws no title bar or frame of its own. Without the extension, the
library likewise draws no decorations. Decoration and transparency preferences
are independent.

The [xdg-decoration protocol](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml)
allows the compositor to override the requested mode. There is no portable
guarantee that a normal Wayland window can suppress compositor borders or focus
indicators. For example, Hyprland 0.56.1 responds with server-side mode even to
client-side requests. Transparency does not override that policy.

## Verification

```sh
./scripts/check-linux.sh
```

This runs rect-cutting frame integration tests, font shaping/cache tests, image decoder tests, Linux GLES
pixel-readback tests, and optimized
builds of all examples. The rendering tests use Mesa's surfaceless EGL platform
and do not require a visible window. They cover rounded corners, alpha blending,
image orientation, tint, draw order, batching, Retina-style scaling, slot reuse,
stale handles, exhausted generations, and the production transparent/opaque
frame clear paths. If needed, run the script with
`LIBGL_ALWAYS_SOFTWARE=1` to exercise Mesa's software driver.

To exercise the same EGL driver as the window (rather than the surfaceless
software renderer), run this inside the graphical session:

```sh
odin test platform -out:bin/platform-tests-wayland -o:speed -vet -strict-style -define:WAYLAND_RENDER_TEST=true
```

This uses the Wayland EGL display and the application's GLES context setup,
rendering into an offscreen framebuffer. It does not open a window.

Then run `./bin/demo3` and check the actual Wayland integration:

- Three images appear; the robot's background is transparent.
- The small robot follows the pointer; left/right holds tint it differently.
- Resizing or changing tiling layout updates the image layout and pointer coordinates.
- Leaving the window clears pointer-inside and held-button state.
- Moving between outputs with different integer scales preserves logical sizing.
- Hiding the window stops rendering; restoring it resumes.
- The compositor's close-window command exits the application normally.

`WAYLAND_DEBUG=1 ./bin/demo3` logs protocol traffic if window creation fails.
The profiler's submission time includes EGL swap waits; it does not measure GPU execution.

## Current boundaries

There is one main window with auxiliary panels and one input seat. Integer
output scaling is supported; fractional scaling is left to the compositor.
Touch input and general client-drawn decorations are not implemented. Server decorations are requested when
`xdg-decoration` is available; otherwise the compositor's window-management
shortcuts can move, resize, and close the window.

Wayland does not expose global pointer position. After pointer leave the snapshot
retains the last known position and clears `mouse_inside` and button flags.
During a drag, implicit pointer grabs can deliver coordinates outside the window.

Animation advances on the shared application timer at a target of 60 updates
per second. Compositor frame callbacks gate presentation only.
Image resources use array slots and generations, just like the Metal backend.
Textures and dimensions are owned by the renderer and released before EGL teardown.

## Validation performed in the Omarchy ARM64 VM

The core capture, editor, text-layout and image-resource integration tests pass
on surfaceless GLES. Platform tests cover pixels, keyboard/mouse snapshots, XKB
text, composition, and clipboard transfers. Native checks cover application and
panel lifecycle, and Hyprland key delivery with cross-client clipboard exchange.

Multi-output scaling and the full interactive checklist above still require
manual verification on the relevant hardware.

## Main window and panels

`ui.create_window` creates one main window; `ui.create_panel` creates auxiliary
panels, defaulting to no decorations (subject to compositor policy). Closing the
main window closes every panel and ends `run`. Panel closure never keeps or ends
the application independently.

One application update deadline drives all builders, including surfaces waiting
for compositor frame callbacks. Input is snapshotted for every participant before
any builder runs. Compositor callbacks gate only presentation. A shared poll loop
services one application Wayland connection. Panels use `xdg_toplevel.set_parent`
to identify the main window as their parent. Each window has its own EGL context,
input snapshot and resources; context switches precede building, drawing and
destruction. Placement, stacking and activation remain compositor policy.

Try `./scripts/build.sh demo12` and `./bin/demo12`. Run
`./scripts/check-windows.sh` in the Wayland session for lifetime/state checks.
See [core/WINDOWS.md](../core/WINDOWS.md) for API and resource ownership.

## Native text input and clipboard

An active `request_text_input` client receives UTF-8 commits and editing commands
separately from physical keys. XKB supplies layout-aware typing, dead-key/Compose
sequences and repeat. Control shortcuts provide selection, copy/cut/paste and
undo/redo; Shift extends navigation selections. Ordinary typing works without
an input-method daemon or the optional `zwp_text_input_manager_v3` protocol.
`ui.text_input_capabilities()` reports typing, composition-protocol and clipboard
availability separately; protocol availability does not imply an installed IME.

When the compositor exposes text-input-v3, the adapter enables it for the focused
text identity and publishes surrounding text and the caret rectangle in logical
surface coordinates. Preedit, commit and surrounding-deletion events are applied
at `done`. Operations retain the identity that owned them, including across focus
changes. Focus/device loss cancels composition. The adapter does not install or
configure an IME; candidate UI and language conversion belong to the compositor's
input method. No v1/v2 text-input protocol fallback is provided.

Clipboard operations use `wl_data_device`, offering and accepting UTF-8 plain
text. Copy requires a focused window and an input serial. Clipboard reads return
an owned string, or false when no supported selection exists or transfer fails.
External reads are bounded to one second and 16 MiB; outgoing transfers are
nonblocking. Selection ownership lasts while the application runs or until
another client takes it. No clipboard utility is required by the backend.

## Mouse transitions and window dragging

Press/release bits accumulate between frames, including a complete click within
one update interval. Pointer leave, device loss and keyboard-focus loss cancel
held interactions instead of activating clicks. Motion remains surface-local
and can extend outside the window during an implicit drag grab.

`set_window_drag_region` publishes a content-local rectangle. A left press in it
requests `xdg_toplevel.move` with that button's serial and cancels the UI click.
An empty region disables application-requested movement. Compositor window
bindings remain available; the compositor decides whether/how to move a window.

## Capture and native input checks

`capture_frames` uses GLES on Mesa's surfaceless EGL platform and writes PNGs
without opening a window. It supports transparent output, explicit scales and
scripted multi-frame input; see [CAPTURE.md](../core/CAPTURE.md). `check-linux.sh`
runs the same core capture/editor/image integration tests and demo capture
scenarios as macOS, as well as native window lifecycle checks.

For a live Hyprland Lua session, this optional test checks native key delivery,
main/panel input isolation and clipboard exchange with another client:

```sh
odin build tests/wayland_input -out:bin/wayland-input-check -o:speed -vet -strict-style
python3 scripts/check-wayland-input.py
```

The test driver requires Python, `hyprctl`, and `wl-clipboard`. It opens its own
windows, injects keys only into those windows, and restores the text clipboard.
Protocol-callback tests additionally cover dead keys, preedit/commit ordering,
surrounding deletion, stale identity events, quick clicks and large/cancelled
clipboard pipe transfers. Live IME candidate placement and multi-output scaling
still need manual verification with the relevant input method and hardware.
