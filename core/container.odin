package ui

import "layout"

Sizing :: layout.Sizing
Insets :: layout.Insets
Direction :: layout.Direction
fixed :: layout.fixed
fit :: layout.fit
insets :: layout.insets

// Layout dimensions are logical points. Fixed dimensions include padding;
// omitted dimensions fit content. An empty fit container is just its padding.
// Painting is kept out of the layout engine. Children do not clip to this box.
Container :: struct {
	layout:        Direction,
	width:         Sizing,
	height:        Sizing,
	padding:       Insets,
	gap:           f32,
	background:    Color,
	corner_radius: f32,
}

// Appends a container and makes it the parent of subsequent declarations.
// Pair with container_close; braces alone do not open or close containers.
// This first layout stage deliberately exposes no stable identity or hover API.
container_open :: proc(container: Container) {
	assert(active_state != nil, "container_open must run inside the window update")
	state := active_state
	layout.open(&state.tree, {
		layout = container.layout,
		width = container.width, height = container.height,
		padding = container.padding, gap = container.gap,
	})
	surface_index := -1
	if container.background.a > 0 {
		surface_index = len(state.frame.surfaces)
		append(&state.frame.surfaces, Surface{
			background = container.background, corner_radius = container.corner_radius,
		})
	}
	append(&state.surface_indices, surface_index)
}

// Restores the previous parent. All opened containers must close before update
// returns; the layout engine checks for both extra closes and missing closes.
container_close :: proc() {
	assert(active_state != nil, "container_close must run inside the window update")
	layout.close(&active_state.tree)
}
