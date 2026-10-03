#!/bin/sh
# Build with system HarfBuzz/FreeType and the vendored static SheenBidi.
set -eu
cd "$(dirname "$0")/.."
target=${1:-demo10}
case "$target" in
    demo[0-9]|demo10|demo11|demo12|demo13|demo14|demo15) source_dir="examples/$target" ;;
    file-manager) source_dir="apps/file-manager" ;;
    *) echo "Usage: $0 [demo0..demo15 | file-manager]" >&2; exit 1 ;;
esac
mkdir -p bin
. ./scripts/text-link-paths.sh
odin build "$source_dir" "-out:bin/$target" -o:speed -vet -strict-style \
    "-extra-linker-flags:$link_paths"
