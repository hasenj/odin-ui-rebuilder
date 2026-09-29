package ui

@(private)
Layer_Scope :: struct {z: i32, clip_depth: int, escape_clip: bool}
@(private)
Surface_Run :: struct {start, end: int, z: i32}
@(private)
Layer_Bucket :: struct {z: i32, count, cursor: int}

// Absolute z-index. Higher layers draw later; declaration order is stable within
// a layer. Layout and identity parenting are unchanged. Popup content may opt
// out of ancestor clips while remaining in the same logical identity subtree.
open_layer :: proc(z: i32, escape_clip: bool = false) {
	flush_surface_state()
	append(&active_state.layers, Layer_Scope{z, len(active_state.clips), escape_clip})
	if escape_clip { append(&active_state.clips, Clip_Scope{}) }
}

close_layer :: proc() {
	assert(active_state != nil && len(active_state.layers) > 0, "Unbalanced close_layer")
	scope := active_state.layers[len(active_state.layers) - 1]
	assert(len(active_state.clips) == scope.clip_depth + (1 if scope.escape_clip else 0), "Unclosed clip in layer")
	flush_surface_state()
	if scope.escape_clip { pop(&active_state.clips) }
	pop(&active_state.layers)
}

@(private)
current_layer :: proc() -> i32 {
	if len(active_state.layers) == 0 { return 0 }
	return active_state.layers[len(active_state.layers) - 1].z
}

// Sort only the small list of distinct layer numbers, then copy runs into their
// bucket. No sorting/comparing of individual glyphs or surfaces. Reuse capacity.
@(private)
order_layers :: proc() {
	state := active_state
	clear(&state.layer_buckets)
	for run in state.surface_runs {
		index := 0
		for index < len(state.layer_buckets) && state.layer_buckets[index].z < run.z { index += 1 }
		if index == len(state.layer_buckets) || state.layer_buckets[index].z != run.z {
			append(&state.layer_buckets, Layer_Bucket{})
			for i := len(state.layer_buckets) - 1; i > index; i -= 1 { state.layer_buckets[i] = state.layer_buckets[i - 1] }
			state.layer_buckets[index] = Layer_Bucket{z = run.z}
		}
		state.layer_buckets[index].count += run.end - run.start
	}
	if len(state.layer_buckets) <= 1 { return }
	offset := 0
	for &bucket in state.layer_buckets {
		bucket.cursor = offset
		offset += bucket.count
	}
	resize(&state.surface_scratch, len(state.frame.surfaces))
	for run in state.surface_runs {
		for &bucket in state.layer_buckets {
			if bucket.z != run.z { continue }
			count := run.end - run.start
			copy(state.surface_scratch[bucket.cursor:bucket.cursor + count], state.frame.surfaces[run.start:run.end])
			bucket.cursor += count
			break
		}
	}
	state.frame.surfaces, state.surface_scratch = state.surface_scratch, state.frame.surfaces
}
