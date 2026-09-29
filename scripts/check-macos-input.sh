#!/bin/sh
# Exercise native wheel/keyboard events and focus on the AppKit main thread.
set -eu
cd "$(dirname "$0")/.."
test "$(uname -s)" = Darwin
mkdir -p bin
. ./scripts/text-link-paths.sh
odin build tests/window_input -out:bin/window-input-check -o:speed -vet -strict-style \
    "-extra-linker-flags:$link_paths"
./bin/window-input-check
