## Project Description:

UI framework where the whole UI is reconstructed each time we update the UI

    [Application Data] -> [UI Structure] -> [Rendering Primitives] -> [Screen Pixels]

The framework provides the API to build the UI structure, then at a later pass
produces the rendering primitives and renders them to the screen.

An implementation of this idea already exists in go.hasen.dev/shirei

This project implements the same paradigm in Odin

## Milestone 0: Basic structure

Establish boundaries between application code, framework, and platform layer.

All code is in pure Odin. When asm is needed, we use Odin's assembly support.

Platform layer: macos platform, open a window

Framework: open a window (defers to platform)

App: calls the framework's open window.

The app exits when the window is closed

Dir structure:

    platform/
    core/
    examples/app0

The core imports only the general platform package. Common files in platform/
define its public procedures and shared types; OS-specific files in the same
package implement them. Odin selects implementations using file suffixes such as
window_darwin.odin. There are no separate platform implementation subpackages.

## Milestone 1: Rendering primitives

core framework defines a rendering primitive: reactangle, rounded corners, background color, size and position

platform layer implements a procedure that takes a list of these primitives and renders them to the screen using the GPU

No "layout" structure at this point, so the app code just manually emits rendering primitives

For the example app, emitting rectangles of various shapes and colors that just move across the screen might a good first test

Since we don't have any sort of input data yet, we only use "time" as the input, and render at 60fps.

Later we will limit rendering frequency.

## Milestone 2: Input as data

Mouse position information is available as data in the framework core, the platform layer makes this information available by writing to a shared structure on core that holds input events.

Frame updates still happen at 60fps

Example app still shows rectangles moving across the screen, but in addition, we show a rectangle that follows the mouse

Input is not an "event"; just data. The app code simply reads the input data form `core` that was written by the `platform`

