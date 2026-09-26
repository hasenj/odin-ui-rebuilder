package platform

import "core:fmt"
import "core:time"

Frame_Timing :: enum {
	Disabled,
	Summary,
	Every_Frame,
}

@(private)
Frame_Profiler :: struct {
	mode:             Frame_Timing,
	frames:           u64,
	previous_start:   time.Tick,
	report_start:     time.Tick,
	count:            int,
	interval_count:   int,
	interval_sum_ms:  f64,
	cpu_sum_ms:       f64,
	cpu_max_ms:       f64,
	update_sum_ms:    f64,
	submit_sum_ms:    f64,
}

// Called after frame cleanup. Printing and statistics bookkeeping are excluded
// from CPU time, but their overhead is reflected in the next callback interval.
@(private)
record_frame_timing :: proc(p: ^Frame_Profiler, start: time.Tick, update_ms, submit_ms: f64, rectangles: int) {
	end := time.tick_now()
	cpu_ms := time.duration_milliseconds(time.tick_diff(start, end))
	interval_ms: f64
	if p.frames > 0 {
		interval_ms = time.duration_milliseconds(time.tick_diff(p.previous_start, start))
		p.interval_sum_ms += interval_ms
		p.interval_count += 1
	} else {
		p.report_start = start
	}
	p.previous_start = start
	p.frames += 1

	if p.mode == .Every_Frame {
		fmt.printf("[frame %d] CPU %.3f ms | update %.3f ms | submit %.3f ms | interval %.3f ms | rectangles %d\n",
			p.frames, cpu_ms, update_ms, submit_ms, interval_ms, rectangles)
		return
	}

	p.count += 1
	p.cpu_sum_ms += cpu_ms
	p.cpu_max_ms = max(p.cpu_max_ms, cpu_ms)
	p.update_sum_ms += update_ms
	p.submit_sum_ms += submit_ms
	if time.tick_diff(p.report_start, end) < time.Second {
		return
	}
	fps: f64
	if p.interval_sum_ms > 0 {
		fps = 1000 * f64(p.interval_count) / p.interval_sum_ms
	}
	n := f64(p.count)
	fmt.printf("[frames %d..%d] CPU avg/max %.3f/%.3f ms | update avg %.3f ms | submit avg %.3f ms | callbacks %.1f/s | rectangles %d\n",
		p.frames - u64(p.count) + 1, p.frames, p.cpu_sum_ms / n, p.cpu_max_ms,
		p.update_sum_ms / n, p.submit_sum_ms / n, fps, rectangles)
	p.report_start = end
	p.count = 0
	p.interval_count = 0
	p.interval_sum_ms = 0
	p.cpu_sum_ms = 0
	p.cpu_max_ms = 0
	p.update_sum_ms = 0
	p.submit_sum_ms = 0
}
