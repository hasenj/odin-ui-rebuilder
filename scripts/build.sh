#!/bin/sh
# Build with system HarfBuzz/FreeType and the vendored static SheenBidi.
set -eu
cd "$(dirname "$0")/.."
app=${1:-app8}
case "$app" in app[0-8]) ;; *) echo "Usage: $0 [app0..app8]" >&2; exit 1 ;; esac
mkdir -p bin
text_deps=$(./scripts/build-text-deps.sh)
odin build "examples/$app" "-out:bin/$app" -o:speed -vet -strict-style \
    "-extra-linker-flags:-L$text_deps $(pkg-config --libs-only-L harfbuzz freetype2)"
