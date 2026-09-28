#!/bin/sh
# Deterministic CPU width sweep; no window or GPU submission.
set -eu
cd "$(dirname "$0")/.."
text_deps=$(./scripts/build-text-deps.sh)
odin test core/text -out:bin/text-resize-bench -o:speed -vet -strict-style \
    -define:TEXT_RESIZE_BENCH=true -define:ODIN_TEST_NAMES=text.resize_benchmark \
    "-extra-linker-flags:-L$text_deps $(pkg-config --libs-only-L harfbuzz freetype2)"
