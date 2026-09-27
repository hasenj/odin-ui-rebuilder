#!/bin/sh
# Build the pinned SheenBidi for the current host; no download or install step.
set -eu
cd "$(dirname "$0")/.."
output="bin/text-deps/$(uname -s)-$(uname -m)"
mkdir -p "$output"
# Rebuild only when a source/header or this script is newer than the archive.
if [ ! -f "$output/libsheenbidi.a" ] || [ -n "$(find third_party/SheenBidi scripts/build-text-deps.sh -type f -newer "$output/libsheenbidi.a" -print 2>/dev/null)" ]; then
    "${CC:-cc}" -O2 -DNDEBUG -DSB_CONFIG_UNITY -fPIC \
        -Ithird_party/SheenBidi/Headers -Ithird_party/SheenBidi/Source \
        -c third_party/SheenBidi/Source/SheenBidi.c -o "$output/SheenBidi.o"
    "${AR:-ar}" rcs "$output/libsheenbidi.a" "$output/SheenBidi.o"
fi
# Used by the build/test scripts as a linker search path.
printf '%s/%s\n' "$PWD" "$output"
