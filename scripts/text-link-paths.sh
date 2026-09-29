# Shared by build/check scripts after changing to the repository root.
# Linux distributions normally put these libraries in the default linker paths.
# macOS/Homebrew needs pkg-config to locate its non-default library directories.
text_deps=$(./scripts/build-text-deps.sh)
link_paths="-L$text_deps"
if command -v pkg-config >/dev/null 2>&1; then
    system_link_paths=$(pkg-config --libs-only-L harfbuzz freetype2)
    link_paths="$link_paths $system_link_paths"
elif [ "$(uname -s)" != Linux ]; then
    echo "pkg-config is required to locate HarfBuzz and FreeType (brew install pkgconf)." >&2
    exit 1
fi
