# System fonts and virtual lists

From the repository root:

```sh
./scripts/build.sh demo17
./bin/demo17
./bin/demo17 --capture
```

Scans conventional OS font directories once at startup, lists family/style
metadata without eagerly loading every face, and lazily opens a selected face.
The initial Helvetica/DejaVu selection uses named lookup. The editable sample
uses automatic fallback for mixed Latin, Japanese and Arabic, with local tofu
where no installed outline font covers a grapheme. Color emoji is not supported.

Rows use `ui.Virtual_List`; scroll, Tab through rows or reverse the list.
The selected font is application data keyed by catalog face, independent of
position. Previewing many faces retains their loaded resources for the window's
lifetime. Catalog scanning is synchronous and explicit in this first version.

Capture writes normal, scrolled and compact PNGs to `bin/` through the production
renderer. Installed fonts are machine-dependent, so screenshots are evidence,
not byte-for-byte golden images. Shared core tests cover insertion/reordering,
focus removal and allocation/resource invariants with deterministic data.
