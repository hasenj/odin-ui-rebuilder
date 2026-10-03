package ui

import "base:runtime"

// One typed record per identity. Address stays stable until the identity is
// removed at frame end or the window closes. Initialization/cleanup run once.
// Use child identities for multiple independent records. Application data that
// outlives the UI (e.g. virtualized file selection) belongs outside this store.
state :: proc($T: typeid, init: proc(^T) = nil, cleanup: proc(^T) = nil, id: Identity = {}) -> ^T {
	id := id
	if id == (Identity{}) { id = current_identity() }
	assert(identity_valid(id), "State requires a live identity in the current window")
	node := &active_state.identities.nodes[id.index - 1]
	if node.state != nil {
		assert(node.state.type == T, "An identity's retained state type cannot change")
		return cast(^T)node.state.data
	}
	Storage :: struct {header: Retained_State, value: T, cleanup: proc(^T)}
	storage := new(Storage)
	storage.header = {type = T, data = &storage.value, allocator = context.allocator,
		destroy = proc(data: rawptr) {
			owned := cast(^Storage)data
			context.allocator = owned.header.allocator
			if owned.cleanup != nil { owned.cleanup(&owned.value) }
			free(owned)
		}}
	storage.cleanup = cleanup
	node.state = &storage.header
	if init != nil { init(&storage.value) }
	return &storage.value
}

@(private) Retained_State :: struct {
	type: typeid,
	data: rawptr,
	allocator: runtime.Allocator,
	destroy: proc(rawptr),
}
