#!/bin/sh
# Native tests and optimized builds on macOS or Linux.
set -eu
cd "$(dirname "$0")/.."
mkdir -p bin
. ./scripts/text-link-paths.sh
for package in core core/text core/images platform; do
    output=$(basename "$package")
    odin test "$package" "-out:bin/$output-tests" -o:speed -vet -strict-style \
        "-extra-linker-flags:$link_paths"
done
odin build tools/capture -out:bin/capture -o:speed -vet -strict-style \
    "-extra-linker-flags:$link_paths"
for app in app0 app1 app2 app3 app4 app5 app6 app7 app8 app9 app10 app11 app12 app13; do
    ./scripts/build.sh "$app"
done

if [ "$(uname -s)" = Darwin ]; then
    ./bin/app10 --capture
    ./bin/app11 --capture
    ./bin/app12 --capture
    ./bin/app13 --capture
    ./scripts/check-macos-input.sh
fi

./scripts/check-windows.sh
