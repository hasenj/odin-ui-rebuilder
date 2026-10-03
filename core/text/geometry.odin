package text

import "../primitives"

// Physical-pixel geometry relative to the line origin. Atlas page indices remain
// valid for the window lifetime: atlas packing is append-only (no repacking).
// Keeping physical geometry lets equivalent font sizes share it across scales.
@(private)
Glyph_Quad :: struct {
	position, size: [2]f32,
	uv: [4]f32,
	page: int,
	line: int,
}

// Lazy: measure() never rasterizes. Borrowed output lasts until the next shape
// or preparation call. A cached run must be the most recently accessed entry.
@(private)
prepare_quads :: proc(store: ^Store, run: Shape) -> ([]Glyph_Quad, Error) {
	if run.cache_index != 0 {
		entry := &store.runs.entries[run.cache_index - 1]
		if entry.prepared { return entry.quads, .None }
	}
	store.geometry_builds += 1
	clear(&store.quad_scratch)
	pen: [2]f32
	line: int
	for info, i in run.infos {
		if len(run.lines) > 0 {
			for line < len(run.lines) - 1 && i >= run.lines[line].end { line += 1 }
			if i == run.lines[line].start { pen = {0, f32(line) * run.line_height} }
		}
		font := run.font
		if len(run.sources) > 0 { font = &store.fonts[int(run.sources[i]) - 1] }
		glyph, err := cache_glyph(store, font, info.codepoint, run.pixel_size, source_weight(font, run.weight))
		if err != .None { return nil, err }
		p := run.positions[i]
		if glyph.page >= 0 {
			offset := [2]f32{f32(p.x_offset) / 64, -f32(p.y_offset) / 64}
			append(&store.quad_scratch, Glyph_Quad{
				position = pen + offset + glyph.bearing + [2]f32{0, run.metrics.ascent},
				size = {f32(glyph.size.x), f32(glyph.size.y)}, page = glyph.page, line = line,
				uv = {f32(glyph.position.x) / ATLAS_SIZE, f32(glyph.position.y) / ATLAS_SIZE,
					f32(glyph.position.x + glyph.size.x) / ATLAS_SIZE, f32(glyph.position.y + glyph.size.y) / ATLAS_SIZE},
			})
		}
		pen += [2]f32{f32(p.x_advance), -f32(p.y_advance)} / 64
	}
	quads := store.quad_scratch[:]
	if run.cache_index == 0 { return quads, .None }
	cache := &store.runs
	entry := &cache.entries[run.cache_index - 1]
	bytes := len(quads) * size_of(Glyph_Quad)
	if run_entry_bytes(entry) + bytes > MAX_RUN_BYTES {
		// Render unusually large runs from scratch storage without caching quads.
		return quads, .None
	}
	assert(cache.first == run.cache_index)
	for cache.bytes + bytes > MAX_RUN_BYTES {
		// This run is pinned at the head and fits on its own; only evict others.
		assert(cache.last != run.cache_index)
		evict_run(cache)
	}
	entry.quads = make([]Glyph_Quad, len(quads))
	copy(entry.quads, quads)
	entry.prepared = true // Including empty/space-only runs with no visible quads.
	cache.bytes += bytes
	return entry.quads, .None
}

// This is all the geometry work performed for each visible glyph on a warm draw.
@(private)
place_quad :: proc(quad: Glyph_Quad, image: primitives.Image, position: [2]f32, color: primitives.Color, scale: f32) -> primitives.Surface {
	return {
		position = position + quad.position / scale,
		size = quad.size / scale,
		background = color, image = image, image_region = quad.uv,
	}
}
