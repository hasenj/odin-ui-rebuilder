#!/bin/sh
# Build an example with system HarfBuzz and FreeType (including Homebrew paths).
set -eu
cd "$(dirname "$0")/.."
app=${1:-app5}
case "$app" in app[0-5]) ;; *) echo "Usage: $0 [app0..app5]" >&2; exit 1 ;; esac
mkdir -p bin
odin build "examples/$app" "-out:bin/$app" -o:speed -vet -strict-style \
    "-extra-linker-flags:$(pkg-config --libs-only-L harfbuzz freetype2)"
