package capture

import "core:fmt"
import "core:os"
import "core:strconv"
import ui "../../core"
import demo4 "../../examples/demo4"
import demo5 "../../examples/demo5"
import demo6 "../../examples/demo6"
import demo7 "../../examples/demo7"
import demo8 "../../examples/demo8"
import demo9 "../../examples/demo9"
import demo10 "../../examples/demo10"
import demo11 "../../examples/demo11"
import demo12 "../../examples/demo12"
import demo13 "../../examples/demo13"
import file_manager "../../apps/file-manager"

// Separate executable: example globals and resource handles start fresh.
main :: proc() {
	if len(os.args) < 3 || len(os.args) > 9 || len(os.args) == 8 {
		fmt.eprintln("Usage: capture <demo4..demo13 | file-manager> output.png [width height scale time [mouse_x mouse_y]]")
		os.exit(1)
	}
	update: ui.Update
	size: [2]f32
	switch os.args[1] {
	case "demo4": update = demo4.update; size = {960, 640}
	case "demo5": update = demo5.update; size = {980, 800}
	case "demo6": update = demo6.update; size = {980, 850}
	case "demo7": update = demo7.update; size = {920, 880}
	case "demo8": update = demo8.update; size = {960, 640}
	case "demo9": update = demo9.update; size = {780, 510}
	case "demo10": update = demo10.update; size = {1000, 760}
	case "demo11": update = demo11.update; size = {1160, 860}
	case "demo12": update = demo12.workspace; size = {660, 700}
	case "demo13": update = demo13.update; size = {920, 700}
	case "file-manager": update = file_manager.update; size = {780, 640}
	case:
		fmt.eprintln("Choose demo4 through demo13, or file-manager")
		os.exit(1)
	}
	item := ui.Capture_Frame{path = os.args[2], size = size, scale = 2}
	if len(os.args) > 3 { item.size.x = f32(number(3)) }
	if len(os.args) > 4 { item.size.y = f32(number(4)) }
	if len(os.args) > 5 { item.scale = f32(number(5)) }
	if len(os.args) > 6 { item.time = number(6) }
	if len(os.args) > 8 {
		item.input = {mouse_position = {f32(number(7)), f32(number(8))}, mouse_inside = true}
	}
	result := ui.capture_frames(update, []ui.Capture_Frame{item})
	if result.error != .None {
		fmt.eprintln("Capture failed:", result.error, "frame:", result.frame_index)
		os.exit(1)
	}
	fmt.println("Saved", item.path)
}

number :: proc(index: int) -> f64 {
	value, ok := strconv.parse_f64(os.args[index])
	if !ok { fmt.eprintln("Invalid number:", os.args[index]); os.exit(1) }
	return value
}
