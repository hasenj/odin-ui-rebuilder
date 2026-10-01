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

main :: proc() {
	ui.init()
	cancelled := ui.create_window("Never realized", 100, 100, cancelled_update)
	ui.request_close(cancelled)
	assert(!ui.window_alive(cancelled))
	primary = ui.create_window("Multi-window primary", 360, 260, primary_update)
	secondary = ui.create_window("Multi-window secondary", 280, 220, secondary_update)
	assert(primary != secondary && ui.window_alive(primary) && ui.window_alive(secondary))
	start_native_checks()
	ui.run()
	stop_native_checks()
	assert(counts[0] >= 3 && counts[1] == 3 && counts[2] == 3 && counts[3] == 2)
	assert(!ui.window_alive(primary) && !ui.window_alive(secondary) && !ui.window_alive(survivor))
	ui.shutdown()

	// Reinitialization must neither re-register ObjC classes nor revive handles.
	ui.init()
	again := ui.create_window("Reinitialized application", 200, 160, final_update)
	assert(again != primary && again != survivor && !ui.window_alive(stale))
	ui.request_close(primary)
	assert(ui.window_alive(again))
	start_native_checks()
	ui.run()
	stop_native_checks()
	assert(!ui.window_alive(again))
	ui.shutdown()
	fmt.println("Verified independent window state/resources, native resize/input, deferred create/close, stale handles, last-window return and reinitialization")
}

cancelled_update :: proc() { panic("A cancelled pending window must not update") }

primary_update :: proc() {
	check_state(0)
	if counts[1] == 3 && !reopened && counts[0] > 3 {
		stale = secondary
		assert(!ui.window_alive(stale))
		secondary = ui.create_window("Multi-window replacement", 280, 220, replacement_update)
		assert(secondary != stale)
		ui.request_close(stale)
		assert(ui.window_alive(secondary))
		reopened = true
	}
	if counts[2] == 3 && native_checks_complete() {
		// Close the final existing window while creating its successor from the
		// same callback. run must keep going until that successor closes too.
		ui.request_close(primary)
		survivor = ui.create_window("Last survivor", 200, 160, survivor_update)
		assert(!ui.window_alive(primary) && ui.window_alive(survivor))
	}
}

secondary_update :: proc() {
	check_state(1)
	if counts[1] == 3 { ui.request_close(ui.current_window()) }
}

replacement_update :: proc() {
	check_state(2)
	if counts[2] == 3 { close_replacement() }
}

survivor_update :: proc() {
	check_state(3)
	assert(!ui.window_alive(primary) && !ui.window_alive(secondary))
	if counts[3] == 2 { ui.request_close(ui.current_window()) }
}

final_update :: proc() {
	assert(ui.current_window() != primary)
	_, found := ui.find_font("test-font")
	assert(!found)
	ui.paint(color = {0.1, 0.2, 0.3, 1})
	quit_application()
}

check_state :: proc(index: int) {
	frame := ui.current_frame()
	assert(ui.window_alive(frame.window))
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
