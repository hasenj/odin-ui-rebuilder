#!/bin/sh
# Deterministic CPU width sweep; no window or GPU submission.
set -eu
cd "$(dirname "$0")/.."
. ./scripts/text-link-paths.sh
odin test core/text -out:bin/text-resize-bench -o:speed -vet -strict-style \
    -define:TEXT_RESIZE_BENCH=true -define:ODIN_TEST_NAMES=text.resize_benchmark \
    "-extra-linker-flags:$link_paths"
