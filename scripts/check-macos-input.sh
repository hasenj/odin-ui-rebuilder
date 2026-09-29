#!/bin/sh
# Exercise native wheel events and frame snapshots on the AppKit main thread.
set -eu
cd "$(dirname "$0")/.."
test "$(uname -s)" = Darwin
mkdir -p bin
odin build tests/window_input -out:bin/window-input-check -o:speed -vet -strict-style
./bin/window-input-check
