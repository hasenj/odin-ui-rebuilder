package text

import "core:testing"
import "core:path/filepath"
import "core:time"
import "core:fmt"

// Opt-in deterministic width sweep, excluding rasterization warm-up and GPU
// waits. Run with -define:TEXT_RESIZE_BENCH=true -define:ODIN_TEST_NAMES=text.resize_benchmark.
@(test)
resize_benchmark :: proc(t: ^testing.T) {
	if !#config(TEXT_RESIZE_BENCH, false) { return }
	store: Store
	defer destroy(&store, nil)
	root := filepath.dir(#location().file_path)
	paths := [?]string{"../../examples/app5/assets/NotoSansDisplay-VariableFont.ttf", "../../examples/app6/assets/Amiri-Regular.ttf"}
	fonts: [2]Font
	for path, i in paths {
		full_path, _ := filepath.join({root, path})
		fonts[i], _ = load(&store, full_path)
		delete(full_path)
	}
	values := [?]string{
		"A paragraph starts with an available width. The text chooses its line breaks, and the resulting height tells us how much space to cut. Measurement and painting share the same prepared layout.\n\nAn explicit blank line is preserved, too.",
		"مرحباً بكم في عالم الواجهات. هذه فقرة عربية تحتوي على كلمات English وأرقام 123، ويتغيّر عدد السطور عندما نغيّر عرض النافذة. السَّلَامُ عَلَيْكُمْ — أَهْلًا وَسَهْلًا بكم!",
	}
	for value, i in values {
		result, err := layout(&store, fonts[i], value, 24, 2, 0, 800)
		assert(err == .None)
		run, _ := resolve_layout(&store, result._request)
		_, err = prepare_quads(&store, run)
		assert(err == .None)
	}
	shapes, bidis := store.shape_calls, store.bidi_calls
	start := time.tick_now()
	for n in 0..<240 {
		for value, i in values {
			result, err := layout(&store, fonts[i], value, 24, 2, 0, 260 + f32(n) * 2)
			assert(err == .None)
			run, _ := resolve_layout(&store, result._request)
			_, err = prepare_quads(&store, run)
			assert(err == .None)
		}
	}
	fmt.printf("RESIZE: %.3f ms/width (two paragraphs), %d shape calls, %d bidi analyses\n", time.duration_milliseconds(time.tick_since(start)) / 240, store.shape_calls - shapes, store.bidi_calls - bidis)
}
