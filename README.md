# Odin UI Rebuilder

A UI framework in Odin that will rebuild the UI from application data on each
update. Milestone 0 establishes a native macOS window and the package boundaries:

- `examples/app0` imports the framework and calls `ui.open_window`.
- `core` exposes the application-facing API and imports only `platform`.
- `platform/window.odin` defines the common platform API.
- `platform/window_darwin.odin` implements that API in the same package, using
  Odin's `core:sys/darwin/Foundation` bindings for the AppKit application, window,
  and event loop. Odin selects this file by its OS suffix.

All project code is Odin. It links to macOS system frameworks through Odin's
bindings; no C or Objective-C source, third-party windowing library, or app bundle
is required.

## Run

On macOS, install Odin and the Xcode Command Line Tools. From the repository root:

```sh
mkdir -p bin
odin run examples/app0 -out:bin/app0
```

The example opens a centered, resizable window with an 800 × 600 point content
area. Closing the window exits the application. Minimizing it keeps it running.
`ui.open_window(title, width = 800, height = 600)` must be called once from the main
thread. It runs the native event loop, and window closure terminates the process
through AppKit; do not rely on code or deferred cleanup after this call.

## Verify

```sh
odin check examples/app0 -vet -strict-style
mkdir -p bin
odin build examples/app0 -out:bin/app0 -vet -strict-style
```

Launch `./bin/app0`, confirm the title and empty content area, resize and minimize/
restore the window, then click its close button. The process should exit normally
and return control to the terminal. Rendering and input data are later milestones.
