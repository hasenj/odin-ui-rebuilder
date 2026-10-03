package text

import "native"
import "core:slice"
import "core:unicode/utf8"

// Logical grapheme range and its visual advance edges in points. Edges run
// right-to-left for RTL text. A selection may therefore produce several spans.
Caret_Span :: struct {start, end: int, leading, trailing: f32}

// Caller-owned geometry, rebuilt when text/style changes. Uses the same shaped
// advances as rendering; ligatures divide their advance among graphemes. Font-
// supplied ligature caret tables are a later precision improvement.
caret_spans :: proc(store: ^Store, font: Font, value: string, size, scale, weight: f32, out: ^[dynamic]Caret_Span, direction: Direction = .Auto, language: string = "") -> (Metrics, Error) {
	clear(out)
	run, err := shape(store, font, value, size * scale, weight, direction, language)
	if err != .None { return {}, err }
	metrics := logical_metrics(run.metrics, scale)
	if len(value) == 0 { return metrics, .None }
	sequence := native.SB_Sequence{encoding = 0, buffer = raw_data(value), length = uintptr(len(value))}
	algorithm := native.SBAlgorithmCreate(&sequence)
	if algorithm == nil { return {}, .Shaping_Failed }
	defer native.SBAlgorithmRelease(algorithm)
	base: u8 = 0xfe if direction == .Auto else 1 if direction == .RTL else 0
	paragraph := native.SBAlgorithmCreateParagraph(algorithm, 0, sequence.length, base)
	if paragraph == nil { return {}, .Shaping_Failed }
	defer native.SBParagraphRelease(paragraph)
	levels := native.SBParagraphGetLevelsPtr(paragraph)[:len(value)]
	clusters := make([dynamic]int, 0, len(run.infos) + 1, context.temp_allocator)
	for glyph in run.infos { append(&clusters, int(glyph.cluster)) }
	append(&clusters, len(value)); slice.sort(clusters[:])
	boundaries := make([dynamic]int, 0, len(value) + 1, context.temp_allocator)
	it := utf8.decode_grapheme_iterator_make(value)
	for { _, grapheme, ok := utf8.decode_grapheme_iterate(&it); if !ok { break }; append(&boundaries, grapheme.byte_index) }
	append(&boundaries, len(value))
	x: f32
	for i := 0; i < len(run.infos); {
		start := int(run.infos[i].cluster)
		end := clusters[upper_bound(clusters[:], start)]
		advance: f32
		for i < len(run.infos) && int(run.infos[i].cluster) == start {
			advance += f32(run.positions[i].x_advance) / (64 * scale); i += 1
		}
		first := max(0, upper_bound(boundaries[:], start) - 1)
		last := max(first + 1, upper_bound(boundaries[:], end - 1))
		count := last - first
		for j in 0..<count {
			a, b := x + advance * f32(j) / f32(count), x + advance * f32(j + 1) / f32(count)
			if levels[start] & 1 != 0 { a, b = x + advance - (a - x), x + advance - (b - x) }
			append(out, Caret_Span{boundaries[first + j], boundaries[first + j + 1], a, b})
		}
		x += advance
	}
	return metrics, .None
}
@(private) upper_bound :: proc(items: []int, value: int) -> int {
	lo, hi := 0, len(items)
	for lo < hi { mid := (lo + hi) / 2; if items[mid] <= value { lo = mid + 1 } else { hi = mid } }
	return lo
}
