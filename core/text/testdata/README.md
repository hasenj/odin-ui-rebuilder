# Arabic shaping reference

`arabic-hb.json` was generated with HarfBuzz 14.2.1's `hb-shape`, using the
bundled unmodified Amiri font. The test compares glyph IDs, original UTF-8 byte
clusters, advances, and mark offsets against this independent command-line run.

```sh
hb-shape examples/app6/assets/Amiri-Regular.ttf 'السَّلَامُ عَلَيْكُمْ' \
  --font-funcs=ft --ft-load-flags=10 --font-size=2048 --direction=rtl \
  --script=Arab --language=ar --bot --eot --utf8-clusters \
  --remove-default-ignorables --no-glyph-names --output-format=json
```

Tests also cover visual run ordering, mirrored parentheses, isolates, join
controls, and warmed bidi/geometry caches. SheenBidi's own upstream tests were
run separately from the pinned v3.0.0 checkout.
