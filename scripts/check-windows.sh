#!/bin/sh
# Native lifecycle checks run on the main thread, outside Odin test workers.
set -eu
cd "$(dirname "$0")/.."
mkdir -p bin
. ./scripts/text-link-paths.sh
odin build tests/windows -out:bin/windows-check -o:speed -vet -strict-style \
    "-extra-linker-flags:$link_paths"
./bin/windows-check
