package text

import "core:testing"
import "core:path/filepath"
import "core:mem"
import "core:fmt"

// Compare the new width-independent cache with the original exact line shaper
// across resizes, bidi controls, Arabic marks, blank lines and variable weights.
@(test)
paragraph_resize_pipeline :: proc(t: ^testing.T) {
	root := filepath.dir(#location().file_path)
	latin_path, _ := filepath.join({root, "../../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
	arabic_path, _ := filepath.join({root, "../../examples/assets/fonts/Amiri-Regular.ttf"})
	defer delete(latin_path)
	defer delete(arabic_path)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	store, reference: Store
	latin, _ := load(&store, latin_path)
	arabic, _ := load(&store, arabic_path)
	_, _ = load(&reference, latin_path)
	_, _ = load(&reference, arabic_path)
	Case :: struct {value: string, font: Font, weight: f32, direction: Direction}
	cases := []Case{
		{"office affinity AVATAR café a\u0308\u0301 words that wrap into lines", latin, 400, .LTR},
		{"bold type mixes small and large words office office office", latin, 900, .Auto},
		{"  a  b  c\n\nlast\r\n", latin, 0, .Auto},
		{"a \u0301b office a \u0308b", latin, 0, .Auto},
		{"office\u00a0office supercalifragilistic tiny", latin, 0, .Auto},
		{"السَّلَامُ عَلَيْكُمْ — أَهْلًا وَسَهْلًا بكم في Odin 2026!", arabic, 0, .Auto},
		{"مرحبابكمالجميع Hello 123! one two three (العربية)", arabic, 0, .Auto},
		{"Hello مرحبا 123 [abc] test (السَّلَامُ) !", arabic, 0, .LTR},
		{"Hello مرحبا 123 [abc] test (السَّلَامُ) !", arabic, 0, .RTL},
		{"abc \u2067مرحبا 123 hello world\u2069 xyz", arabic, 0, .LTR},
		{"abc \u202bمرحبا 123 hello world\u202c xyz", arabic, 0, .LTR},
		{"مرحبا\u2028Hello 123!\u2028\u2028last", arabic, 0, .Auto},
		{"\u2067\u2069 \u200f  \u202b\u202c abc", arabic, 0, .Auto},
	}
	for item in cases {
		for i in 0..<30 {
			width := f32(i * 13)
			actual, err := shape(&store, item.font, item.value, 32, item.weight, item.direction, "", width)
			assert(err == .None)
			base, _ := shape(&reference, item.font, "", 32, item.weight, item.direction)
			assert(configure_font(base.font, base.pixel_size, base.weight) == .None)
			base.cache_index = 0
			assert(shape_wrapped_reference(&reference, &base, item.value, width, item.direction, "") == .None)
			if actual.metrics != base.metrics || len(actual.infos) != len(base.infos) { fmt.printf("Mismatch %q width %f\n", item.value, width) }
			testing.expect_value(t, actual.metrics, base.metrics)
			testing.expect_value(t, len(actual.lines), len(base.lines))
			testing.expect_value(t, len(actual.infos), len(base.infos))
			if len(actual.lines) != len(base.lines) || len(actual.infos) != len(base.infos) { continue }
			for line, j in actual.lines { testing.expect_value(t, line, base.lines[j]) }
			for info, j in actual.infos {
				testing.expect_value(t, info.codepoint, base.infos[j].codepoint)
				testing.expect_value(t, info.cluster, base.infos[j].cluster)
				testing.expect_value(t, actual.positions[j], base.positions[j])
			}
			quads, _ := prepare_quads(&store, actual)
			expected, _ := prepare_quads(&reference, base)
			testing.expect_value(t, len(quads), len(expected))
			if len(quads) == len(expected) {
				for quad, j in quads {
					testing.expect_value(t, quad.position, expected[j].position)
					testing.expect_value(t, quad.size, expected[j].size)
				}
			}
		}
	}

	// Ordinary Latin and Arabic word wrapping needs no new bidi analysis or
	// shaping across widths never seen before, after paragraph preparation.
	for item in ([]Case{cases[0], cases[1], cases[5], cases[6]}) {
		_, _ = shape(&store, item.font, item.value, 32, item.weight, item.direction, "", 1000)
		shapes, bidis := store.shape_calls, store.bidi_calls
		for i in 0..<50 {
			_, err := shape(&store, item.font, item.value, 32, item.weight, item.direction, "", 100 + f32(i) * 1.25)
			assert(err == .None)
		}
		testing.expect_value(t, store.shape_calls, shapes)
		testing.expect_value(t, store.bidi_calls, bidis)
	}

	// An actual unsafe boundary: the V in AVATAR is kerned with A. Slicing
	// cached glyphs there would retain the wrong advance; reshape restores it.
	base, _ := shape(&store, latin, "", 32, 400)
	key := Run_Key{font = latin, pixel_size = base.pixel_size, weight = base.weight, value = "AVATAR office"}
	entry, cache_error := get_paragraph(&store, base.font, key)
	assert(cache_error == .None)
	testing.expect(t, !entry.safe[1])
	testing.expect(t, !reuse_paragraph_line(&store, entry, 0, 1))
	fallbacks := store.wrap_reshapes
	advance, boundary_error := paragraph_line_width(&store, base.font, entry, 0, 1)
	testing.expect_value(t, boundary_error, Error.None)
	testing.expect_value(t, store.wrap_reshapes, fallbacks + 1)
	isolated, _ := measure(&store, latin, "A", 32, 1, 400)
	testing.expect_value(t, advance, isolated.width)

	// Paragraph keys own stack-backed strings; LRU reuse must not depend on the
	// current font face configuration or on retaining the original caller buffer.
	buffer: [64]u8
	value := fmt.bprintf(buffer[:], "ephemeral paragraph %d", 17)
	_, _ = shape(&store, latin, value, 28, 400, .Auto, "en", 130)
	for &ch in buffer { ch = 'X' }
	_, _ = shape(&store, latin, "other font size", 48, 900)
	shapes, bidis := store.shape_calls, store.bidi_calls
	_, _ = shape(&store, latin, "ephemeral paragraph 17", 28, 400, .Auto, "en", 135)
	testing.expect_value(t, store.shape_calls, shapes)
	testing.expect_value(t, store.bidi_calls, bidis)
	for i in 0..<MAX_PARAGRAPHS + 1 {
		value = fmt.bprintf(buffer[:], "evict paragraph %d", i)
		_, _ = shape(&store, latin, value, 24, 400, .Auto, "", 140)
	}
	testing.expect_value(t, len(store.paragraphs.lookup), MAX_PARAGRAPHS)
	testing.expect(t, store.paragraphs.bytes <= MAX_PARAGRAPH_BYTES)
	bytes: int
	for &entry in store.paragraphs.entries { if entry.paragraph != nil { bytes += paragraph_bytes(&entry) } }
	testing.expect_value(t, bytes, store.paragraphs.bytes)
	// Rebuild an evicted paragraph and verify its output once more.
	result, err := layout(&store, latin, "office affinity", 32, 1, 400, 95)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, result.line_count == 2)
	// Byte-budget eviction and an oversized paragraph's uncached fallback.
	long_text := make([]u8, 20_000)
	for &ch in long_text { ch = 'a' }
	for i in 0..<6 {
		long_text[0] = 'a' + u8(i)
		_, _ = shape(&store, latin, string(long_text), 24, 400, .Auto, "", 400)
	}
	testing.expect(t, store.paragraphs.bytes <= MAX_PARAGRAPH_BYTES)
	testing.expect(t, len(store.paragraphs.lookup) < MAX_PARAGRAPHS)
	delete(long_text)
	large := make([]u8, 100_000)
	for &ch in large { ch = 'a' }
	bytes_before := store.paragraphs.bytes
	_, err = shape(&store, latin, string(large), 24, 400, .Auto, "", 400)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, store.paragraphs.scratch.paragraph == nil)
	testing.expect_value(t, store.paragraphs.bytes, bytes_before)
	delete(large)

	destroy(&store, nil)
	destroy(&reference, nil)
	testing.expect_value(t, len(tracking.allocation_map), 0)
}
