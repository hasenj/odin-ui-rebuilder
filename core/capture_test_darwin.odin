package ui

import "core:testing"
import "core:path/filepath"
import "core:os"
import "core:image/png"
import "core:image"

// Called by rect_frame_pipeline, keeping use of the implicit UI context serial.
// Public UI API -> real Metal -> encoded PNG -> independent Odin PNG decoder.
@(private)
capture_pipeline :: proc(t: ^testing.T) {
	paths: [3]string
	names := [?]string{"capture-test-normal.png", "capture-test-hover.png", "capture-test-empty.png"}
	for name, i in names {
		paths[i], _ = filepath.join({filepath.dir(#location().file_path), "../bin", name})
	}
	defer for path in paths { delete(path) }
	capture_test_font = 0
	capture_test_image = {}
	defer { capture_test_font = 0; capture_test_image = {} }
	frames := [?]Capture_Frame{
		{path = paths[0], size = {160, 100}, scale = 1},
		// No file: establish the new hover target at the old timestamp.
		{size = {160, 100}, scale = 1, input = {mouse_inside = true, mouse_position = {20, 20}}},
		{path = paths[1], size = {200, 120}, scale = 2, time = 0.1,
		 input = {mouse_inside = true, mouse_position = {20, 20}}},
		{path = paths[2], size = {160, 100}, scale = 1, time = 1},
	}
	result := capture_frames(capture_test_scene, frames[:])
	if !testing.expect_value(t, result.error, Capture_Error.None) { return }
	testing.expect_value(t, result.frame_index, -1)
	for path, i in paths {
		decoded, err := png.load(path)
		if !testing.expect(t, err == nil) { continue }
		defer image.destroy(decoded)
		width := 400 if i == 1 else 160
		height := 240 if i == 1 else 100
		testing.expect_value(t, decoded.width, width)
		testing.expect_value(t, decoded.height, height)
		testing.expect_value(t, decoded.channels, 4)
		pixels := decoded.pixels.buf[:]
		if i == 2 {
			for component in pixels {
				if !testing.expect_value(t, component, u8(0)) { break }
			}
			continue
		}
		scale := 2 if i == 1 else 1
		// Half-alpha red panel; after one half-life, it is half red / half blue.
		p := ((20 * scale) * width + 20 * scale) * 4
		expected := [4]u8{255, 0, 0, 128} if i == 0 else [4]u8{128, 0, 128, 128}
		for channel in 0..<4 {
			testing.expect(t, abs(int(pixels[p + channel]) - int(expected[channel])) <= 2)
		}
		// Unpainted/rounded corner must remain transparent. Image top-left is red.
		testing.expect_value(t, pixels[3], u8(0))
		p = ((10 * scale) * width + 75 * scale) * 4
		testing.expect_value(t, pixels[p], u8(255))
		testing.expect_value(t, pixels[p + 3], u8(255))
		// Text region must contain glyph coverage, including the first atlas upload.
		coverage := 0
		for y in 60 * scale..<90 * scale {
			for x in 0..<width { coverage += int(pixels[(y * width + x) * 4 + 3]) }
		}
		testing.expect(t, coverage > 0)
	}
	// A file error must be reported, not silently counted as a successful capture.
	bad_path, _ := filepath.join({paths[0], "not-a-directory.png"})
	bad := Capture_Frame{path = bad_path, size = {16, 16}, scale = 1}
	defer delete(bad_path)
	result = capture_frames(nil, []Capture_Frame{bad})
	testing.expect_value(t, result.error, Capture_Error.Write_Failed)
	testing.expect_value(t, result.frame_index, 0)
	bad.path = ""
	bad.scale = 0
	result = capture_frames(nil, []Capture_Frame{bad})
	testing.expect_value(t, result.error, Capture_Error.Invalid_Frame)
	// Avoid leaving test artifacts; the command-line runner retains its captures.
	for path in paths { _ = os.remove(path) }
}

@(private) capture_test_font: Font
@(private) capture_test_image: Image

@(private)
capture_test_scene :: proc() {
	if current_frame().time == 1 { return }
	if capture_test_font == 0 {
		path, _ := filepath.join({filepath.dir(#location().file_path), "../examples/assets/fonts/NotoSansDisplay-VariableFont.ttf"})
		defer delete(path)
		err: Text_Error
		capture_test_font, err = load_font(path)
		assert(err == .None)
		image_error: Image_Error
		capture_test_image, image_error = load_image_from_bytes(#load("images/testdata/rgba.png", []u8))
		assert(image_error == nil)
	}
	open_rect(.Top, 50)
	{
		open_rect(.Left, 50)
		amount := animate_f32(1 if hovered() else 0, half_life = 0.1)
		paint(color = {1 - amount, 0, amount, 0.5}, corners = 12)
		close_rect()
		pad4(0, 0, 0, 20)
		open_rect(.Left, 40)
		paint(img = capture_test_image)
		close_rect()
	}
	close_rect()
	pad4(10, 0, 0, 0)
	_, err := text("Capture café", capture_test_font, size = 20)
	assert(err == .None)
}
