package capture

import "core:fmt"
import "core:os"
import "core:strconv"
import ui "../../core"
import app4 "../../examples/app4"
import app5 "../../examples/app5"
import app6 "../../examples/app6"
import app7 "../../examples/app7"
import app8 "../../examples/app8"
import app9 "../../examples/app9"
import app10 "../../examples/app10"
import app11 "../../examples/app11"
import app12 "../../examples/app12"

// Separate executable: example globals and resource handles start fresh.
main :: proc() {
	if len(os.args) < 3 || len(os.args) > 9 || len(os.args) == 8 {
		fmt.eprintln("Usage: capture app4..app12 output.png [width height scale time [mouse_x mouse_y]]")
		os.exit(1)
	}
	update: ui.Update
	size: [2]f32
	switch os.args[1] {
	case "app4": update = app4.update; size = {960, 640}
	case "app5": update = app5.update; size = {980, 800}
	case "app6": update = app6.update; size = {980, 850}
	case "app7": update = app7.update; size = {920, 880}
	case "app8": update = app8.update; size = {960, 640}
	case "app9": update = app9.update; size = {780, 510}
	case "app10": update = app10.update; size = {1000, 760}
	case "app11": update = app11.update; size = {1160, 860}
	case "app12": update = app12.workspace; size = {660, 700}
	case:
		fmt.eprintln("Choose app4 through app12")
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
