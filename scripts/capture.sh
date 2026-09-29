#!/bin/sh
# Run from any directory; output paths are relative to the repository root.
set -eu
cd "$(dirname "$0")/.."
mkdir -p bin
. ./scripts/text-link-paths.sh
odin build tools/capture -out:bin/capture -o:speed -vet -strict-style \
    "-extra-linker-flags:$link_paths"
exec ./bin/capture "$@"
