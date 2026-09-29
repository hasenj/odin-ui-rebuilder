#!/bin/sh
# Native tests and optimized builds on macOS or Linux.
set -eu
cd "$(dirname "$0")/.."
mkdir -p bin
text_deps=$(./scripts/build-text-deps.sh)
link_paths="-L$text_deps $(pkg-config --libs-only-L harfbuzz freetype2)"
for package in core core/text core/images platform; do
    output=$(basename "$package")
    odin test "$package" "-out:bin/$output-tests" -o:speed -vet -strict-style \
        "-extra-linker-flags:$link_paths"
done
for app in app0 app1 app2 app3 app4 app5 app6 app7 app8 app9; do
    ./scripts/build.sh "$app"
done
