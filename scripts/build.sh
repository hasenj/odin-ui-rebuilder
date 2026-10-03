#!/bin/sh
# Build with system HarfBuzz/FreeType and the vendored static SheenBidi.
set -eu
cd "$(dirname "$0")/.."
app=${1:-app10}
case "$app" in app[0-9]|app10|app11|app12|app13|app14) ;; *) echo "Usage: $0 [app0..app14]" >&2; exit 1 ;; esac
mkdir -p bin
. ./scripts/text-link-paths.sh
odin build "examples/$app" "-out:bin/$app" -o:speed -vet -strict-style \
    "-extra-linker-flags:$link_paths"
