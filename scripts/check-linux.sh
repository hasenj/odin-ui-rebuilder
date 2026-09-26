#!/bin/sh
# Run from any directory inside a Linux installation with Odin and Mesa.
set -eu
cd "$(dirname "$0")/.."
mkdir -p bin
odin test core/layout -out:bin/layout-tests -o:speed -vet -strict-style
odin test core -out:bin/core-tests -o:speed -vet -strict-style
odin test core/images -out:bin/image-tests -o:speed -vet -strict-style
odin test platform -out:bin/platform-tests -o:speed -vet -strict-style
for app in app0 app1 app2 app3 app4; do
    odin build "examples/$app" "-out:bin/$app" -o:speed -vet -strict-style
done
