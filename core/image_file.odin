package ui

import "files"
import "core:strings"
import "../platform"

Load_State :: files.State
Image_File :: struct {image: Image, state: Load_State, error: string}
@(private) Image_File_Key :: struct {path: string, max_extent: int, watch: bool}
@(private) Image_File_Record :: struct {task: ^files.Task, image: Image, error: string, used: u64}
@(private) Image_File_Store :: struct {service: ^files.Service, records: map[Image_File_Key]Image_File_Record, frame: u64}

// Nonblocking, window-owned cache. First use queues IO/decoding on a worker;
// repeated calls return the same image. Done can carry an error. Watching polls
// metadata off-thread and preserves the previous image until a reload succeeds.
// max_extent optionally downsamples on the worker (useful for thumbnails).
// Returned handles/errors are borrowed: do not destroy them or retain them
// across eviction. At most 128 cached entries; current-frame entries are pinned.
image_file :: proc(path: string, watch: bool = true, max_extent: int = 0) -> Image_File {
	frame := current_frame()
	store := &active_state.image_files
	if store.service == nil {
		store.service = files.create()
		store.records = make(map[Image_File_Key]Image_File_Record)
	}
	key := Image_File_Key{path, max(0, max_extent), watch}
	record := &store.records[key]
	if record == nil {
		if len(store.records) >= 128 {
			oldest: Image_File_Key
			found := false
			age := store.frame
			for candidate, item in store.records {
				if item.used < age { oldest, age, found = candidate, item.used, true }
			}
			if !found { return {state = .Done, error = "Image cache full for this frame"} }
			old := store.records[oldest]
			files.release(store.service, old.task)
			platform.destroy_image(frame.renderer, old.image)
			delete(old.error)
			delete_key(&store.records, oldest)
			delete(oldest.path)
		}
		key.path = strings.clone(path)
		store.records[key] = Image_File_Record{task = files.request(store.service, path, .Image, watch, max_extent)}
		record = &store.records[key]
	}
	if record.used != store.frame {
		if result, ready := files.take(store.service, record.task); ready {
			delete(record.error)
			record.error = strings.clone(result.error)
			if result.error == "" {
				image, err := platform.create_image(frame.renderer, result.pixels, result.size)
				if err == .None {
					platform.destroy_image(frame.renderer, record.image)
					record.image = image
				} else { record.error = strings.clone("Could not upload image") }
			}
			files.retire(store.service, result)
		}
	}
	record.used = store.frame
	return {record.image, files.status(store.service, record.task), record.error}
}

// Emit nothing until the first decode/upload finishes. Paints the last good
// image during reload, using the ordinary paint sizing/corner semantics.
paint_image :: proc(path: string, corners: f32 = 0, color: Color = {1, 1, 1, 1}, watch: bool = true, max_extent: int = 0) -> Image_File {
	result := image_file(path, watch, max_extent)
	if result.image != (Image{}) { paint(color = color, img = result.image, corners = corners) }
	return result
}

@(private) destroy_image_files :: proc(store: ^Image_File_Store) {
	files.destroy(store.service)
	for key, record in store.records { delete(key.path); delete(record.error) }
	delete(store.records)
	// Renderer teardown owns GPU resources, just as for synchronous images.
	store^ = {}
}
