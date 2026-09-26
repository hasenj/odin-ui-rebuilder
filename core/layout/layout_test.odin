package layout

import "core:testing"

// Full nested tree -> resolved geometry. Unequal dimensions/padding catch axis
// swaps; a nested sibling catches accidental use of descendants as siblings.
@(test)
nested_rows_columns :: proc(t: ^testing.T) {
	tree: Tree
	defer destroy(&tree)
	reset(&tree, {800, 600})
	outer := open(&tree, {padding = {3, 5, 7, 11}, gap = 13})
	row := open(&tree, {layout = .Row, padding = {2, 4, 6, 8}, gap = 9})
	a := open(&tree, {width = fixed(20), height = fixed(10)})
	close(&tree)
	b := open(&tree, {width = fixed(30), height = fixed(16)})
	close(&tree)
	close(&tree)
	column := open(&tree, {padding = insets(1), gap = 3})
	c := open(&tree, {width = fixed(12), height = fixed(7)})
	close(&tree)
	d := open(&tree, {width = fixed(8), height = fixed(9)})
	close(&tree)
	close(&tree)
	close(&tree)
	after := open(&tree, {width = fixed(4), height = fixed(6)})
	close(&tree)
	resolve(&tree)
	testing.expect_value(t, tree.sizes[0], [2]f32{800, 600})
	testing.expect_value(t, tree.sizes[row], [2]f32{67, 28})
	testing.expect_value(t, tree.sizes[column], [2]f32{14, 21})
	testing.expect_value(t, tree.sizes[outer], [2]f32{77, 78})
	testing.expect_value(t, tree.positions[row], [2]f32{3, 5})
	testing.expect_value(t, tree.positions[a], [2]f32{5, 9})
	testing.expect_value(t, tree.positions[b], [2]f32{34, 9})
	testing.expect_value(t, tree.positions[column], [2]f32{3, 46})
	testing.expect_value(t, tree.positions[c], [2]f32{4, 47})
	testing.expect_value(t, tree.positions[d], [2]f32{4, 57})
	testing.expect_value(t, tree.positions[after], [2]f32{0, 78})
}

@(test)
fixed_fit_empty_and_overflow :: proc(t: ^testing.T) {
	tree: Tree
	defer destroy(&tree)
	reset(&tree, {100, 100})
	row := open(&tree, {layout = .Row, width = fixed(10), padding = {1, 2, 3, 4}, gap = 5})
	large := open(&tree, {width = fixed(20), height = fixed(30)})
	close(&tree)
	empty := open(&tree, {padding = {2, 3, 4, 5}, gap = 100})
	close(&tree)
	zero := open(&tree, {width = fixed(0), height = fixed(0), padding = insets(9)})
	close(&tree)
	close(&tree)
	resolve(&tree)
	testing.expect_value(t, tree.sizes[row], [2]f32{10, 36})
	testing.expect_value(t, tree.sizes[empty], [2]f32{6, 8})
	testing.expect_value(t, tree.sizes[zero], [2]f32{})
	testing.expect_value(t, tree.positions[large], [2]f32{1, 2})
	testing.expect_value(t, tree.positions[empty], [2]f32{26, 2})
	testing.expect_value(t, tree.positions[zero], [2]f32{37, 2})
	// Rebuild after resize and removal; neither geometry nor child counts survive.
	reset(&tree, {320, 240})
	only := open(&tree, {layout = .Row, padding = insets(2), gap = 50})
	open(&tree, {width = fixed(11), height = fixed(13)})
	close(&tree)
	close(&tree)
	resolve(&tree)
	testing.expect_value(t, len(tree.nodes), 3)
	testing.expect_value(t, tree.sizes[0], [2]f32{320, 240})
	testing.expect_value(t, tree.sizes[only], [2]f32{15, 17})
	testing.expect_value(t, tree.positions[2], [2]f32{2, 2})
}

@(test)
large_and_deep_trees :: proc(t: ^testing.T) {
	tree: Tree
	defer destroy(&tree)
	reset(&tree, {100, 100})
	row := open(&tree, {layout = .Row, gap = 1})
	for _ in 0..<10_000 {
		open(&tree, {width = fixed(2), height = fixed(3)})
		close(&tree)
	}
	close(&tree)
	resolve(&tree)
	testing.expect_value(t, tree.sizes[row], [2]f32{29_999, 3})
	testing.expect_value(t, tree.positions[len(tree.nodes) - 1], [2]f32{29_997, 0})
	// Deep nesting uses the same two scans; there is no recursive layout stack.
	reset(&tree, {100, 100})
	for _ in 0..<10_000 {
		open(&tree, {padding = insets(1)})
	}
	leaf := open(&tree, {width = fixed(2), height = fixed(3)})
	close(&tree)
	for _ in 0..<10_000 {
		close(&tree)
	}
	resolve(&tree)
	testing.expect_value(t, tree.sizes[1], [2]f32{20_002, 20_003})
	testing.expect_value(t, tree.positions[leaf], [2]f32{10_000, 10_000})
}
