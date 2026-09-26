package ui

import "images"
import "primitives"
import "../platform"

Image :: primitives.Image
Image_Error :: union #shared_nil {images.Error, platform.Image_Error}

// Call from update, once per asset, then retain the handle across frames.
// PNG and JPEG decoding to RGBA8 is supported (16-bit images are rejected).
// Paths are relative to the working directory.
// Encoded and decoded CPU storage is freed after the one-time GPU upload.
load_image :: proc(frame: ^Frame, path: string) -> (Image, Image_Error) {
	decoded, err := images.load_file(path)
	if err != nil {
		return {}, err
	}
	defer images.destroy(decoded)
	return upload_image(frame, decoded)
}

// The bytes may come from #load, a file, or another source. They are not retained.
load_image_from_bytes :: proc(frame: ^Frame, data: []u8) -> (Image, Image_Error) {
	decoded, err := images.load_bytes(data)
	if err != nil {
		return {}, err
	}
	defer images.destroy(decoded)
	return upload_image(frame, decoded)
}

// Call from update when the image is no longer needed. Clears this handle;
// other copies become invalid and are skipped if emitted. Already submitted
// GPU work retains its own references until completion.
destroy_image :: proc(frame: ^Frame, image: ^Image) {
	platform.destroy_image(frame.renderer, image^)
	image^ = {}
}

@(private)
upload_image :: proc(frame: ^Frame, decoded: ^images.Decoded) -> (Image, Image_Error) {
	image, err := platform.create_image(frame.renderer, decoded.pixels.buf[:], {decoded.width, decoded.height})
	if err != .None {
		return {}, err
	}
	return image, nil
}
