package ui

import "base:runtime"
import "base:intrinsics"

// Window-owned retained node. Slots are generational; zero is invalid.
Identity :: struct {index, generation: u32}

// Explicit integer keys replace the caller location, preserving their type.
// Repeated keys are distinguished by their occurrence under the current parent.
open_identity :: proc{open_identity_implicit, open_identity_keyed}

current_identity :: proc() -> Identity {
	assert(active_state != nil, "Identity calls must run inside the window update")
	return active_state.identities.stack[len(active_state.identities.stack) - 1].id
}

identity_valid :: proc(id: Identity) -> bool {
	assert(active_state != nil, "Identity calls must run inside the window update")
	store := &active_state.identities
	if id.index == 0 || int(id.index) > len(store.nodes) { return false }
	node := &store.nodes[id.index - 1]
	return node.alive && node.generation == id.generation
}

close_identity :: proc() {
	identity_leave(.Identity)
}

@(private)
open_identity_implicit :: proc(loc := #caller_location) -> Identity {
	return identity_enter(Identity_Key{location = loc}, .Identity)
}

@(private)
open_identity_keyed :: proc(key: $T) -> Identity where intrinsics.type_is_integer(T) {
	return identity_enter(integer_identity_key(key), .Identity)
}

@(private)
integer_identity_key :: proc(key: $T) -> Identity_Key where intrinsics.type_is_integer(T) {
	return Identity_Key{integer_type = T, integer = u128(key)}
}

@(private)
Identity_Key :: struct {
	integer_type: typeid,
	integer: u128,
	location: runtime.Source_Code_Location,
}

@(private)
Identity_Group :: struct {parent: Identity, key: Identity_Key}
@(private)
Identity_Path :: struct {group: Identity_Group, occurrence: u32}
@(private)
Identity_Count :: struct {frame: u64, count: u32}
@(private)
Identity_Scope_Kind :: enum {Root, Identity, Rect, Scroll, Layout_Root, Layout_Box}
@(private)
Identity_Scope :: struct {id: Identity, kind: Identity_Scope_Kind}
@(private)
Identity_Node :: struct {
	path: Identity_Path,
	generation: u32,
	alive: bool,
	seen_frame: u64,
	state: ^Retained_State,
	first_child, last_child, next_sibling: Identity,
}
@(private)
Identity_Store :: struct {
	nodes: [dynamic]Identity_Node,
	free: [dynamic]u32,
	stack: [dynamic]Identity_Scope,
	lookup: map[Identity_Path]Identity,
	counts: map[Identity_Group]Identity_Count,
	animations: map[Identity]Animation_F32,
	frame: u64,
}

@(private)
identity_begin_frame :: proc(store: ^Identity_Store) {
	if len(store.nodes) == 0 {
		store.lookup = make(map[Identity_Path]Identity)
		store.counts = make(map[Identity_Group]Identity_Count)
		store.animations = make(map[Identity]Animation_F32)
		append(&store.nodes, Identity_Node{generation = 1, alive = true})
	}
	assert(store.frame != max(u64), "Identity frame counter exhausted")
	store.frame += 1
	root := &store.nodes[0]
	root.seen_frame = store.frame
	root.first_child, root.last_child = {}, {}
	clear(&store.stack)
	append(&store.stack, Identity_Scope{Identity{1, root.generation}, .Root})
}

@(private)
identity_enter :: proc(key: Identity_Key, kind: Identity_Scope_Kind) -> Identity {
	parent := current_identity()
	store := &active_state.identities
	group := Identity_Group{parent, key}
	// Update an existing counter in place instead of hashing the group again
	// for writeback. Do not retain this pointer across insertions into counts.
	counter := &store.counts[group]
	if counter == nil {
		store.counts[group] = Identity_Count{}
		counter = &store.counts[group]
	}
	if counter.frame != store.frame { counter^ = Identity_Count{frame = store.frame} }
	path := Identity_Path{group, counter.count}
	assert(counter.count != max(u32), "Too many occurrences of one identity key")
	counter.count += 1
	id, found := store.lookup[path]
	if !found {
		index: u32
		if len(store.free) > 0 {
			index = pop(&store.free)
		} else {
			assert(len(store.nodes) < int(max(u32)), "Identity slots exhausted")
			append(&store.nodes, Identity_Node{generation = 1})
			index = u32(len(store.nodes))
		}
		node := &store.nodes[index - 1]
		node.path, node.alive = path, true
		id = Identity{index, node.generation}
		store.lookup[path] = id
	}
	node := &store.nodes[id.index - 1]
	node.seen_frame = store.frame
	node.first_child, node.last_child, node.next_sibling = {}, {}, {}
	p := &store.nodes[parent.index - 1]
	if p.last_child.index == 0 {
		p.first_child = id
	} else {
		store.nodes[p.last_child.index - 1].next_sibling = id
	}
	p.last_child = id
	append(&store.stack, Identity_Scope{id, kind})
	return id
}

@(private)
identity_leave :: proc(kind: Identity_Scope_Kind) {
	assert(active_state != nil, "Identity calls must run inside the window update")
	stack := &active_state.identities.stack
	assert(len(stack) > 1, "Cannot close the root identity")
	assert(stack[len(stack) - 1].kind == kind, "Identity and rect scopes must close in nesting order")
	pop(stack)
}

// Disappeared nodes lose their state at the end of this frame. Reusing a slot
// cannot revive an old handle. Current-frame tree links contain only live nodes.
@(private)
identity_end_frame :: proc(store: ^Identity_Store) {
	assert(len(store.stack) == 1, "Unclosed identities at end of update")
	for &node, i in store.nodes {
		if !node.alive || node.seen_frame == store.frame { continue }
		id := Identity{u32(i + 1), node.generation}
		delete_key(&store.lookup, node.path)
		if store.counts[node.path.group].frame != store.frame {
			delete_key(&store.counts, node.path.group)
		}
		delete_key(&store.animations, id)
		if node.state != nil { node.state.destroy(node.state) }
		generation := node.generation
		node = Identity_Node{generation = generation}
		if generation != max(u32) {
			node.generation += 1
			append(&store.free, id.index)
		}
	}
}

@(private)
destroy_identities :: proc(store: ^Identity_Store) {
	for node in store.nodes { if node.state != nil { node.state.destroy(node.state) } }
	delete(store.nodes)
	delete(store.free)
	delete(store.stack)
	delete(store.lookup)
	delete(store.counts)
	delete(store.animations)
	store^ = {}
}
