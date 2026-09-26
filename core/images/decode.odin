package images

import "core:image"
@(require) import "core:image/png"
@(require) import "core:image/jpeg"

Decoded :: image.Image
Error :: image.Error
destroy :: image.destroy

// Decode into top-to-bottom RGBA8 with premultiplied alpha. Premultiplication
// before texture filtering avoids colored fringes around transparent edges.
load_file :: proc(path: string) -> (^Decoded, Error) {
	decoded, err := image.load(path, {.alpha_add_if_missing, .alpha_premultiply})
	return finish_decode(decoded, err)
}

load_bytes :: proc(data: []u8) -> (^Decoded, Error) {
	decoded, err := image.load(data, {.alpha_add_if_missing, .alpha_premultiply})
	return finish_decode(decoded, err)
}

@(private)
finish_decode :: proc(decoded: ^Decoded, err: Error) -> (^Decoded, Error) {
	if err != nil {
		// Some decoders return a partially allocated image on failure.
		destroy(decoded)
		return nil, err
	}
	if decoded.depth != 8 || decoded.channels != 4 {
		destroy(decoded)
		return nil, image.General_Image_Error.Unsupported_Format
	}
	return decoded, nil
}
