package images

import "core:testing"

@(test)
decode_png_pixels_and_errors :: proc(t: ^testing.T) {
	encoded := #load("testdata/rgba.png", []u8)
	decoded, err := load_bytes(encoded)
	if !testing.expect(t, err == nil) {
		return
	}
	defer destroy(decoded)
	testing.expect_value(t, decoded.width, 2)
	testing.expect_value(t, decoded.height, 2)
	expected := [?]u8{255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 128, 128, 0, 0, 0, 0}
	testing.expect_value(t, len(decoded.pixels.buf), len(expected))
	for value, i in expected {
		testing.expect_value(t, decoded.pixels.buf[i], value)
	}

	missing, missing_error := load_file("this-file-does-not-exist.png")
	testing.expect(t, missing == nil && missing_error != nil)
	invalid, invalid_error := load_bytes([]u8{1, 2, 3})
	testing.expect(t, invalid == nil && invalid_error != nil)
	truncated, truncated_error := load_bytes(encoded[:24])
	testing.expect(t, truncated == nil && truncated_error != nil)
}

@(test)
decode_sample_images :: proc(t: ^testing.T) {
	assets := [?][]u8{
		#load("../../examples/demo3/assets/coast.png", []u8),
		#load("../../examples/demo3/assets/oranges.png", []u8),
		#load("../../examples/demo3/assets/robot.png", []u8),
		#load("testdata/rgb.jpg", []u8),
	}
	for data, i in assets {
		decoded, err := load_bytes(data)
		if !testing.expect(t, err == nil) {
			continue
		}
		testing.expect(t, decoded.width > 0 && decoded.height > 0)
		testing.expect_value(t, len(decoded.pixels.buf), decoded.width * decoded.height * 4)
		if i == 2 {
			has_transparent, has_opaque: bool
			for pixel in 0..<decoded.width * decoded.height {
				alpha := decoded.pixels.buf[pixel * 4 + 3]
				has_transparent ||= alpha == 0
				has_opaque ||= alpha == 255
			}
			testing.expect(t, has_transparent && has_opaque, "Robot must retain real alpha transparency")
		}
		if i == 3 {
			testing.expect_value(t, decoded.width, 2)
			testing.expect_value(t, decoded.height, 2)
			for pixel in 0..<decoded.width * decoded.height {
				testing.expect_value(t, decoded.pixels.buf[pixel * 4 + 3], u8(255))
			}
		}
		destroy(decoded)
	}
}
