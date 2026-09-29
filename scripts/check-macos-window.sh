#!/bin/sh
# Exercise actual NSWindow/MTKView options on the AppKit main thread.
set -eu
cd "$(dirname "$0")/.."
test "$(uname -s)" = Darwin
. ./scripts/text-link-paths.sh
odin build tests/window_options -out:bin/window-options-check -o:speed -vet -strict-style \
    "-extra-linker-flags:$link_paths"
for decorations in decorated borderless; do
    for background in opaque transparent default; do
        ./bin/window-options-check "$decorations" "$background"
    done
done
