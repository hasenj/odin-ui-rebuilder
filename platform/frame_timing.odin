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
	wall_sum_ms:      f64,
	wall_max_ms:      f64,
	update_sum_ms:    f64,
	submit_sum_ms:    f64,
	waits_sum_ms:     f64,
}

// Frame wall = update + submit + measured waits + setup/cleanup overhead.
// Called after frame cleanup. Printing and statistics bookkeeping are excluded
// from frame wall time, but their overhead is reflected in the next callback interval.
@(private)
record_frame_timing :: proc(p: ^Frame_Profiler, start: time.Tick, update_ms: f64, render_time: Render_Timing, surfaces: int) {
	end := time.tick_now()
	wall_ms := time.duration_milliseconds(time.tick_diff(start, end))
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
		fmt.printf("[frame %d] frame wall %.3f ms | update %.3f ms | submit %.3f ms | waits %.3f ms | interval %.3f ms | surfaces %d\n",
			p.frames, wall_ms, update_ms, render_time.submit_ms, render_time.waits_ms, interval_ms, surfaces)
		return
	}

	p.count += 1
	p.wall_sum_ms += wall_ms
	p.wall_max_ms = max(p.wall_max_ms, wall_ms)
	p.update_sum_ms += update_ms
	p.submit_sum_ms += render_time.submit_ms
	p.waits_sum_ms += render_time.waits_ms
	if time.tick_diff(p.report_start, end) < time.Second {
		return
	}
	fps: f64
	if p.interval_sum_ms > 0 {
		fps = 1000 * f64(p.interval_count) / p.interval_sum_ms
	}
	n := f64(p.count)
	fmt.printf("[frames %d..%d] frame wall avg/max %.3f/%.3f ms | update avg %.3f ms | submit avg %.3f ms | waits avg %.3f ms | callbacks %.1f/s | surfaces %d\n",
		p.frames - u64(p.count) + 1, p.frames, p.wall_sum_ms / n, p.wall_max_ms,
		p.update_sum_ms / n, p.submit_sum_ms / n, p.waits_sum_ms / n, fps, surfaces)
	p.report_start = end
	p.count = 0
	p.interval_count = 0
	p.interval_sum_ms = 0
	p.wall_sum_ms = 0
	p.wall_max_ms = 0
	p.update_sum_ms = 0
	p.submit_sum_ms = 0
	p.waits_sum_ms = 0
}
