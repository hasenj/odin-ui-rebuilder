#!/bin/sh
# Native tests and optimized builds on macOS or Linux.
set -eu
cd "$(dirname "$0")/.."
mkdir -p bin
. ./scripts/text-link-paths.sh
for package in core core/text core/images core/files platform apps/file-manager; do
    output=$(basename "$package")
    odin test "$package" "-out:bin/$output-tests" -o:speed -vet -strict-style \
        "-extra-linker-flags:$link_paths"
done
odin build tools/capture -out:bin/capture -o:speed -vet -strict-style \
    "-extra-linker-flags:$link_paths"
for target in demo0 demo1 demo2 demo3 demo4 demo5 demo6 demo7 demo8 demo9 demo10 demo11 demo12 demo13 file-manager; do
    ./scripts/build.sh "$target"
done

if [ "$(uname -s)" = Darwin ]; then
    ./bin/demo10 --capture
    ./bin/demo11 --capture
    ./bin/demo12 --capture
    ./bin/demo13 --capture
    ./bin/file-manager --capture
    ./scripts/check-macos-input.sh
fi

./scripts/check-windows.sh
