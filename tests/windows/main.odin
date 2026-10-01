package windows_test

import ui "../../core"
import "../../platform"
import "core:fmt"
import "core:os"

primary, secondary, stale, survivor: ui.Window
counts: [4]int
frames: [4]^ui.Frame
renderers: [4]platform.Renderer
images: [4]ui.Image
reopened: bool

cycle_time: f64
last_order: int
closing_cycle: bool
observer_finished, final_panel_ran: bool

main :: proc() {
	ui.init()
	primary = ui.create_window("Multi-window primary", 360, 260, primary_update)
	cancelled := ui.create_panel("Never realized", 100, 100, cancelled_update)
	ui.close_panel(cancelled)
	secondary = ui.create_panel("Multi-window secondary", 280, 220, secondary_update)
	survivor = ui.create_panel("Observer panel", 240, 200, observer_update)
	start_native_checks()
	ui.run()
	stop_native_checks()
	assert(counts[0] >= 10 && counts[1] == 3 && counts[2] == 3 && counts[3] == counts[0])
	assert(observer_finished && !ui.window_alive(survivor) && !ui.window_alive(primary))
	ui.shutdown()

	ui.init()
	again := ui.create_window("Reinitialized application", 200, 160, final_update)
	ui.create_panel("Quit cleanup panel", 200, 160, final_panel_update)
	assert(again != primary && !ui.window_alive(stale))
	ui.request_close(primary)
	assert(ui.window_alive(again))
	start_native_checks()
	ui.run()
	stop_native_checks()
	assert(final_panel_ran && !ui.window_alive(again))
	ui.shutdown()
	fmt.println("Verified main/panel lifetimes, synchronized cycles/input snapshots, hidden-panel updates, native presentation isolation, resources and stale handles")
}

cancelled_update :: proc() { panic("A cancelled pending panel must not update") }

primary_update :: proc() {
	cycle_time = ui.current_frame().time
	last_order = 0
	check_state(0)
	if counts[1] == 3 && !reopened {
		stale = secondary
		secondary = ui.create_panel("Multi-window replacement", 280, 220, replacement_update, decorated = true)
		assert(secondary != stale)
		ui.close_panel(stale)
		assert(ui.panel_alive(secondary))
		reopened = true
	}
	if counts[2] == 3 && counts[0] >= 10 && native_checks_complete() {
		ui.create_panel("Pending shutdown panel", 100, 100, cancelled_update)
		closing_cycle = true
		close_main()
		assert(ui.create_panel("Rejected after main close", 100, 100, cancelled_update) == (ui.Panel{}))
	}
}

secondary_update :: proc() {
	assert(last_order == 0)
	last_order = 1
	check_state(1)
	if counts[1] == 3 { ui.close_panel(ui.current_window()) }
}

replacement_update :: proc() {
	// The observer is older even though the replacement reuses a lower slot.
	assert(last_order == 3)
	last_order = 2
	check_state(2)
	if counts[2] == 3 { close_replacement() }
}

observer_update :: proc() {
	assert(last_order == 0 || last_order == 1)
	last_order = 3
	check_state(3)
	assert(counts[3] == counts[0], "A presentation/occlusion event skipped or duplicated a builder")
	if closing_cycle {
		assert(!ui.window_alive(primary) && !ui.window_alive(survivor))
		observer_finished = true // Membership remains fixed through the closing cycle.
	}
}

final_update :: proc() {
	_, found := ui.find_font("test-font")
	assert(!found)
	quit_application()
}

final_panel_update :: proc() {
	assert(!ui.panel_alive(ui.current_window()))
	final_panel_ran = true
}

check_state :: proc(index: int) {
	frame := ui.current_frame()
	assert(ui.window_alive(frame.window) || closing_cycle)
	assert(frame.time == cycle_time, "Builders must share the same cycle timestamp")
	counts[index] += 1
	if counts[index] > 600 { fmt.eprintln("Window test timed out"); os.exit(1) }
	if counts[index] == 1 {
		frames[index] = frame
		renderers[index] = frame.renderer
		if index == 1 || index == 2 {
			assert(frame != frames[0] && frame.renderer != renderers[0])
		}
		_, found := ui.find_font("test-font")
		assert(!found, "Fonts leaked across windows")
		_, err := ui.load_font("examples/assets/fonts/NotoSansDisplay-VariableFont.ttf", "test-font")
		assert(err == .None)
		pixel := [4]u8{u8(50 + index * 40), 100, 200, 255}
		image, image_err := platform.create_image(frame.renderer, pixel[:], {1, 1})
		assert(image_err == .None)
		images[index] = image
	} else {
		assert(frame == frames[index] && frame.renderer == renderers[index])
	}
	assert(ui.current_window() == frame.window)
	size, valid := ui.image_size(images[index])
	assert(valid && size == ([2]int{1, 1}), "Another window's destruction damaged this renderer")
	ui.paint(color = {0.05, 0.08, 0.12, 1})
	ui.open_rect(.Top, 40, key = 1)
	ui.focusable()
	if counts[index] == 1 && index != 1 { ui.request_focus() }
	if counts[index] > 1 { assert(ui.focused() == (index != 1), "Focus leaked across windows") }
	_, text_err := ui.text("Window-owned atlas", "test-font", 18)
	assert(text_err == .None)
	ui.close_rect()
	ui.open_scroll({300, 2000}, key = 2)
	if counts[index] == 1 { ui.scroll_to({0, f32((index + 1) * 50)}) }
	assert(ui.current_scroll().offset.y == f32((index + 1) * 50), "Scroll state leaked across windows")
	assert(ui.animate_f32(f32(index), key = 3) == f32(index), "Animation state leaked across windows")
	ui.close_scroll()
	check_native_frame(index)
}
