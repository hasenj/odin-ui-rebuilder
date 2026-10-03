package demo3

import ui "../../core"
import "core:fmt"
import "core:math"
import "core:os"

images: [3]ui.Image
loaded: bool

main :: proc() {
	// Optional file paths replace the three embedded examples:
	// odin run examples/demo3 -out:bin/demo3 -o:speed -- a.png b.jpg c.png
	// Image alpha shows the checkerboard; the window itself stays opaque.
	ui.open_window("Odin UI Rebuilder — images", 1040, 720, update, frame_timing = .Summary, transparent = false)
}

load_images :: proc() {
	embedded := [?][]u8{
		#load("assets/coast.png", []u8),
		#load("assets/oranges.png", []u8),
		#load("assets/robot.png", []u8),
	}
	for data, i in embedded {
		err: ui.Image_Error
		if len(os.args) > i + 1 {
			images[i], err = ui.load_image(os.args[i + 1])
		} else {
			images[i], err = ui.load_image_from_bytes(data)
		}
		if err != nil {
			fmt.eprintln("Could not load image", i + 1, err)
			os.exit(1)
		}
	}
	loaded = true
}

update :: proc() {
	frame := ui.current_frame()
	if !loaded {
		load_images()
	}
	// Only primitive data is rebuilt. Decoding and texture uploads happen once.
	margin: f32 = 32
	gap: f32 = 20
	width := max((frame.size.x - 2 * margin - 2 * gap) / 3, 1)
	height := max(min(frame.size.y - 2 * margin, 470), 1)
	for image, i in images {
		image_size, ok := ui.image_size(image)
		if !ok {
			continue
		}
		position := [2]f32{margin + f32(i) * (width + gap), margin}
		// A checkerboard makes alpha and rounded image corners visible.
		append(&frame.surfaces, ui.Surface{
			position = position, size = {width, height},
			background = {0.12, 0.15, 0.2, 1}, corner_radius = 16,
		})
		for y: f32 = 16; y < height - 16; y += 24 {
			for x: f32 = 16; x < width - 16; x += 24 {
				shade: f32 = 0.22 if (int(x / 24) + int(y / 24)) % 2 == 0 else 0.3
				append(&frame.surfaces, ui.Surface{
					position = position + [2]f32{x, y},
					size = {min(24, width - 16 - x), min(24, height - 16 - y)},
					background = {shade, shade, shade, 1},
				})
			}
		}
		// Preserve aspect ratio while fitting the image within its panel.
		available := [2]f32{max(width - 32, 1), max(height - 32, 1)}
		scale := min(available.x / f32(image_size.x), available.y / f32(image_size.y))
		size := [2]f32{f32(image_size.x), f32(image_size.y)} * scale
		append(&frame.surfaces, ui.Surface{
			position = position + ([2]f32{width, height} - size) * 0.5,
			size = size, background = {1, 1, 1, 1}, corner_radius = 18, image = image,
		})
	}
	// Reuse the robot texture for a moving, translucent image above the panels.
	opacity := 0.55 + 0.35 * math.sin(f32(frame.time))
	position := [2]f32{
		frame.size.x * 0.5 + 120 * math.sin(f32(frame.time) * 0.7) - 50,
		frame.size.y - 145,
	}
	if frame.input.mouse_inside {
		position = frame.input.mouse_position - [2]f32{50, 60}
	}
	tint: ui.Color = {1, 1, 1, opacity}
	if .Left in frame.input.mouse_buttons {
		tint = {1, 0.45, 0.2, 1}
	} else if .Right in frame.input.mouse_buttons {
		tint = {0.3, 0.6, 1, 1}
	}
	append(&frame.surfaces, ui.Surface{
		position = position, size = {100, 120}, background = tint, image = images[2],
	})
}
