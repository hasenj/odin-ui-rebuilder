package file_manager

import ui "../../core"
import "core:fmt"
import "core:time"
import "core:strings"

benchmark_frame: int
benchmark_start: time.Tick
benchmark_us: f64

// The interval spans 1,000 complete warm UI updates, including core identity,
// focus and surface bookkeeping and capture-loop overhead. No GPU submission,
// readback or filesystem access. Font/atlas loading is in the 100 warmup frames.
benchmark_list :: proc() {
	frames := make([]ui.Capture_Frame, 1101)
	defer delete(frames)
	for &frame, i in frames { frame = {size = {780, 640}, scale = 2, time = f64(i) / 60} }
	for count in ([]int{20, 2000, 20000}) {
		browser = Browser{initialized = true, path = strings.clone("/synthetic"), generation = 1}
		for i in 0..<count {
			name := fmt.aprintf("Entry %06d.txt", i)
			append(&browser.entries, Entry{info = {name = name, fullpath = name}})
		}
		font = 0
		benchmark_frame = 0
		result := ui.capture_frames(benchmark_update, frames)
		assert(result.error == .None)
		fmt.printf("%d entries: %.3f us/update (warm, no presentation)\n", count, benchmark_us)
		destroy_browser(&browser)
		destroy_list()
	}
}

benchmark_update :: proc() {
	if benchmark_frame == 100 { benchmark_start = time.tick_now() }
	if benchmark_frame == 1100 { benchmark_us = time.duration_microseconds(time.tick_since(benchmark_start)) / 1000 }
	update()
	benchmark_frame += 1
}
