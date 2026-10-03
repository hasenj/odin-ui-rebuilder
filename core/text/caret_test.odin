package text

import "core:testing"
import "core:path/filepath"
import "core:unicode/utf8"

@(test)
caret_geometry_pipeline :: proc(t: ^testing.T) {
	path, _ := filepath.join({filepath.dir(#location().file_path), "../../examples/assets/fonts/Amiri-Regular.ttf"})
	defer delete(path)
	store: Store
	defer destroy(&store, nil)
	font, err := load(&store, path); assert(err == .None)
	spans: [dynamic]Caret_Span
	defer delete(spans)
	for value in ([]string{"office cafe\u0301", "مرحبا بالعالم", "abc سلام 123", "", "a"}) {
		metrics, error := caret_spans(&store, font, value, 24, 2, 0, &spans)
		testing.expect_value(t, error, Error.None)
		measured, measure_error := measure(&store, font, value, 24, 2, 0)
		testing.expect_value(t, measure_error, Error.None)
		testing.expect_value(t, metrics, measured)
		// Every grapheme has selectable geometry, with no caret inside a
		// combining sequence. All advances cover exactly the rendered width.
		iterator := utf8.decode_grapheme_iterator_make(value)
		for {
			_, g, ok := utf8.decode_grapheme_iterate(&iterator); if !ok { break }
			found := false
			for span in spans { if span.start == g.byte_index && span.end == g.byte_index + len(g.text) { found = true } }
			testing.expect(t, found)
		}
		width: f32
		for span in spans {
			testing.expect(t, span.start < span.end && span.end <= len(value))
			testing.expect(t, min(span.leading, span.trailing) >= -0.001 && max(span.leading, span.trailing) <= metrics.width + 0.001)
			width += abs(span.trailing - span.leading)
		}
		testing.expect(t, abs(width - metrics.width) < 0.001)
		if value == "مرحبا بالعالم" { for span in spans { testing.expect(t, span.leading >= span.trailing) } }
	}
}
