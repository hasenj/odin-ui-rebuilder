// Pure geometry: no rendering, input, stable identities, or platform dependencies.
package layout

Direction :: enum u8 {Column, Row}
Sizing_Kind :: enum u8 {Fit, Fixed}
Sizing :: struct {kind: Sizing_Kind, value: f32}
Insets :: struct {left, top, right, bottom: f32}

Attributes :: struct {
	layout:  Direction,
	width:   Sizing,
	height:  Sizing,
	padding: Insets,
	gap:     f32,
}

// Nodes are appended in preorder. An index is valid only for this build; it is
// not a stable identity. The implicit root is index 0 and has parent -1.
Node :: struct {parent: int, child_count: int}

Tree :: struct {
	nodes:      [dynamic]Node,
	attributes: [dynamic]Attributes,
	sizes:      [dynamic][2]f32,
	positions:  [dynamic][2]f32,
	cursors:    [dynamic]f32, // Scratch: distance along each parent's main axis.
	current:    int,
	resolved:   bool,
}

fixed :: proc(value: f32) -> Sizing {
	assert(valid_length(value), "Fixed dimensions must be finite and nonnegative")
	return {.Fixed, value}
}

fit :: proc() -> Sizing {
	return {}
}

insets :: proc(all: f32) -> Insets {
	return {all, all, all, all}
}

// Begin a new build, retaining all backing allocations. Root size is the window's
// logical size; its children flow downwards. Resolve once after closing all nodes.
reset :: proc(tree: ^Tree, viewport: [2]f32) {
	clear(&tree.nodes)
	clear(&tree.attributes)
	clear(&tree.sizes)
	clear(&tree.positions)
	clear(&tree.cursors)
	tree.current = -1
	tree.resolved = false
	open(tree, {width = fixed(viewport.x), height = fixed(viewport.y)})
}

destroy :: proc(tree: ^Tree) {
	delete(tree.nodes)
	delete(tree.attributes)
	delete(tree.sizes)
	delete(tree.positions)
	delete(tree.cursors)
	tree^ = {}
}

// Returns an internal, frame-local index. Appending may relocate any array;
// retain indices, never pointers into the arrays, while constructing the tree.
open :: proc(tree: ^Tree, attributes: Attributes) -> int {
	assert(!tree.resolved, "Reset before building another layout")
	assert(valid_length(attributes.width.value) && valid_length(attributes.height.value))
	assert(valid_length(attributes.gap), "Gap must be finite and nonnegative")
	p := attributes.padding
	assert(valid_length(p.left) && valid_length(p.top) && valid_length(p.right) && valid_length(p.bottom), "Padding must be finite and nonnegative")
	parent := tree.current
	assert(parent >= 0 || len(tree.nodes) == 0, "Layout has no current parent")
	index := len(tree.nodes)
	append(&tree.nodes, Node{parent = parent})
	append(&tree.attributes, attributes)
	append(&tree.sizes, [2]f32{})
	append(&tree.positions, [2]f32{})
	append(&tree.cursors, f32(0))
	if parent >= 0 {
		tree.nodes[parent].child_count += 1
	}
	tree.current = index
	return index
}

close :: proc(tree: ^Tree) {
	assert(!tree.resolved && tree.current > 0, "Unbalanced container_close")
	tree.current = tree.nodes[tree.current].parent
}

// Fixed sizes describe the outer box, including padding. Fit sizes include all
// direct children plus padding and exactly child_count-1 gaps. Children may
// overflow a fixed parent; this version neither shrinks nor clips them.
resolve :: proc(tree: ^Tree) {
	assert(len(tree.nodes) > 0 && tree.current == 0, "Unclosed containers at end of layout")
	assert(!tree.resolved, "Resolve once per build; reset before the next frame")
	// Pass 1: reverse preorder. Every child's final size is known before its
	// parent is finalized. sizes also holds the accumulating child extents.
	for i := len(tree.nodes) - 1; i >= 0; i -= 1 {
		attrs := tree.attributes[i]
		node := tree.nodes[i]
		main := main_axis(attrs.layout)
		size := tree.sizes[i] + [2]f32{attrs.padding.left + attrs.padding.right, attrs.padding.top + attrs.padding.bottom}
		size[main] += attrs.gap * f32(max(node.child_count - 1, 0))
		if attrs.width.kind == .Fixed {
			size.x = attrs.width.value
		}
		if attrs.height.kind == .Fixed {
			size.y = attrs.height.value
		}
		assert(valid_length(size.x) && valid_length(size.y), "Layout dimensions overflowed")
		tree.sizes[i] = size
		if node.parent >= 0 {
			parent_axis := main_axis(tree.attributes[node.parent].layout)
			tree.sizes[node.parent][parent_axis] += size[parent_axis]
			tree.sizes[node.parent][1 - parent_axis] = max(tree.sizes[node.parent][1 - parent_axis], size[1 - parent_axis])
		}
	}
	// Pass 2: forward preorder. Each parent is positioned before its children.
	// Its cursor advances only for direct children, skipping nested descendants.
	for i in 1..<len(tree.nodes) {
		parent := tree.nodes[i].parent
		attrs := tree.attributes[parent]
		main := main_axis(attrs.layout)
		position := tree.positions[parent] + [2]f32{attrs.padding.left, attrs.padding.top}
		position[main] += tree.cursors[parent]
		tree.positions[i] = position
		tree.cursors[parent] += tree.sizes[i][main] + attrs.gap
	}
	tree.resolved = true
}

@(private)
main_axis :: proc(direction: Direction) -> int {
	return 0 if direction == .Row else 1
}

@(private)
valid_length :: proc(value: f32) -> bool {
	return value >= 0 && value <= max(f32)
}
