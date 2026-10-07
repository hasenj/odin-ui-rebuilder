package text

import "core:testing"
import "core:path/filepath"
import "core:mem"

@(test)
system_catalog_pipeline :: proc(t: ^testing.T) {
	root, _ := filepath.join({filepath.dir(#location().file_path), "../../examples/assets/fonts"})
	defer delete(root)
	path, _ := filepath.join({root, "NotoSansDisplay-VariableFont.ttf"}); defer delete(path)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	store: Store
	latin, err := load(&store, path, "App font"); assert(err == .None)
	value := "Hello مرحبا بالعالم café"
	before, e := shape(&store, latin, value, 24, 0); assert(e == .None)
	missing := false
	for info in before.infos { missing ||= info.codepoint == 0 }
	testing.expect(t, missing)

	count, scan_error := discover_fonts(&store, []string{root, root, "/nonexistent-font-directory"})
	testing.expect_value(t, scan_error, Error.None)
	testing.expect(t, count >= 3)
	testing.expect_value(t, len(store.fonts), 1) // Metadata discovery loads no shaping faces.
	run, error := shape(&store, latin, value, 24, 0); assert(error == .None)
	for info in run.infos { testing.expect(t, info.codepoint != 0) }
	testing.expect(t, len(store.fonts) > 1 && len(store.fonts) < count + 1)
	_, error = prepare_quads(&store, run); assert(error == .None)
	arabic, found := find(&store, "amiri regular")
	testing.expect(t, found && arabic != 0)
	stack, stack_error := font_stack(&store, []Font{latin, arabic}, "Explicit"); assert(stack_error == .None)
	explicit, explicit_error := shape(&store, stack, "مرحبا", 24, 0); assert(explicit_error == .None)
	for source in explicit.sources { testing.expect_value(t, source, arabic) }
	// Negative choices must be reused across new strings, not just shape hits.
	_, error = shape(&store, latin, "A \U0010ffff", 24, 0); assert(error == .None)
	q := store.catalog.queries
	_, error = shape(&store, latin, "B \U0010ffff", 24, 0); assert(error == .None)
	testing.expect(t, store.catalog.queries <= q + 1)
	_, error = shape(&store, latin, value, 24, 0, wrap_width = 500); assert(error == .None)
	shapes, queries := store.shape_calls, store.catalog.queries
	allocations := tracking.total_allocation_count
	for _ in 0..<20 {
		cached, ce := shape(&store, latin, value, 24, 0); assert(ce == .None)
		_, ce = prepare_quads(&store, cached); assert(ce == .None)
		_, _ = find(&store, "amiri regular")
	}
	testing.expect_value(t, tracking.total_allocation_count, allocations)
	for i in 0..<20 { _, error = shape(&store, latin, value, 24, 0, wrap_width = 160 + f32(i)); assert(error == .None) }
	testing.expect_value(t, store.shape_calls, shapes)
	testing.expect_value(t, store.catalog.queries, queries)
	// Refresh invalidates negative coverage and cached tofu, but keeps handles.
	generation := store.catalog_generation
	_, scan_error = discover_fonts(&store, []string{root}); assert(scan_error == .None)
	testing.expect_value(t, store.catalog_generation, generation + 1)
	refreshed, re := shape(&store, latin, value, 24, 0); assert(re == .None)
	for info in refreshed.infos { testing.expect(t, info.codepoint != 0) }
	destroy(&store, nil)
	testing.expect_value(t, len(tracking.allocation_map), 0)
}
