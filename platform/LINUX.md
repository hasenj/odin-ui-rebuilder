# Linux / Wayland

The Linux backend uses native Wayland (xdg-shell), EGL, and OpenGL ES 3.0.
The implementation and protocol metadata are Odin; shaders are GLSL ES 3.00. No GLFW,
SDL, C source compilation, or protocol-generation step is required to build.
Core continues to import the general `platform` package. Odin selects `_linux`
and `_darwin` files for the target OS.

## Build and run in Omarchy

Use a recent Odin compiler with `core:image` PNG/JPEG support and `vendor:egl`.
Development cross-checks used `dev-2026-05-nightly`. Run the following from the
repository root inside the VM:

```sh
sudo pacman -S --needed base-devel wayland libglvnd mesa
mkdir -p bin
odin build examples/app3 -out:bin/app3 -o:speed -vet -strict-style
./bin/app3
```

`wayland` supplies the [client, cursor, and EGL-window libraries](https://archlinux.org/packages/extra/x86_64/wayland/files/).
`libglvnd` supplies [libEGL](https://archlinux.org/packages/extra/x86_64/libglvnd/files/),
and [Mesa](https://archlinux.org/packages/extra/x86_64/mesa/) supplies OpenGL drivers.
Wayland client 1.20+ is required for `wl_proxy_marshal_array_flags`.

Run the application from a terminal in the graphical Wayland session, as your
normal user. `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` must refer to that session;
running it through an unrelated SSH session or with sudo will not set those up.
The app0–app4 examples target either platform; app3 embeds its assets, and app4
demonstrates nested rect cuts, padding, and painting.

For a VM without working accelerated OpenGL, try Mesa software rendering:

```sh
LIBGL_ALWAYS_SOFTWARE=1 ./bin/app3
```

Software-rendered timing numbers do not represent GPU-accelerated performance.
The backend requires OpenGL ES 3.0; it does not fall back to X11 or XWayland.

Desktop OpenGL and GLES capabilities can differ on VM drivers. In the Omarchy
ARM64 VM, the Wayland `virgl` driver accepts GLES 3.0 but rejects a desktop
OpenGL 3.3 core context with `EGL_BAD_MATCH`. The renderer uses GLES 3.0 for
instancing, vertex arrays, and its shaders. Odin's `vendor:OpenGL` supplies the
shared function bindings; loading those bindings does not select desktop GL.

## Verification

```sh
./scripts/check-linux.sh
```

This runs rect-cutting frame integration tests, image decoder tests, Linux GLES
pixel-readback tests, and optimized
builds of all examples. The rendering tests use Mesa's surfaceless EGL platform
and do not require a visible window. They cover rounded corners, alpha blending,
image orientation, tint, draw order, batching, Retina-style scaling, slot reuse,
stale handles, and exhausted generations. If needed, run the script with
`LIBGL_ALWAYS_SOFTWARE=1` to exercise Mesa's software driver.

To exercise the same EGL driver as the window (rather than the surfaceless
software renderer), run this inside the graphical session:

```sh
odin test platform -out:bin/platform-tests-wayland -o:speed -vet -strict-style -define:WAYLAND_RENDER_TEST=true
```

This uses the Wayland EGL display and the application's GLES context setup,
rendering into an offscreen framebuffer. It does not open a window.

Then run `./bin/app3` and check the actual Wayland integration:

- Three images appear; the robot's background is transparent.
- The small robot follows the pointer; left/right holds tint it differently.
- Resizing or changing tiling layout updates the image layout and pointer coordinates.
- Leaving the window clears pointer-inside and held-button state.
- Moving between outputs with different integer scales preserves logical sizing.
- Hiding the window stops rendering; restoring it resumes.
- The compositor's close-window command exits the application normally.

`WAYLAND_DEBUG=1 ./bin/app3` logs protocol traffic if window creation fails.
The profiler's submission time includes EGL swap waits; it does not measure GPU execution.

## Current boundaries

There is one window and one pointer seat. Integer output scaling is supported;
fractional scaling is left to the compositor. There is no keyboard, scroll,
touch, or client-drawn title bar yet. Server decorations are requested when
`xdg-decoration` is available; otherwise the compositor's window-management
shortcuts can move, resize, and close the window.

Wayland does not expose global pointer position. After pointer leave the snapshot
retains the last known position and clears `mouse_inside` and button flags.
During a drag, implicit pointer grabs can deliver coordinates outside the window.

Animation uses compositor frame callbacks and is capped at 60 updates per second.
Image resources use array slots and generations, just like the Metal backend.
Textures and dimensions are owned by the renderer and released before EGL teardown.

## Validation performed in the Omarchy ARM64 VM

The image decoder tests and GLES pixel-readback tests passed, and all four
examples built with `-o:speed -vet -strict-style`. Pixel tests passed on both
surfaceless Mesa `llvmpipe` (software) and Wayland Mesa `virgl` (VM acceleration).
The rebuilt app3 opened as a native Wayland window and rendered its images.

Multi-output scaling and the full interactive checklist above still require
manual verification on the relevant hardware.
