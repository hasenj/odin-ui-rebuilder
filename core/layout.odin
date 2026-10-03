package ui

import "base:intrinsics"
import fonts "text"

Layout_Flow :: enum {Column, Row}
Layout_Size_Mode :: enum {Content, Fixed}
Layout_Size :: struct {mode: Layout_Size_Mode, value: f32}
layout_fixed :: proc(value: f32) -> Layout_Size { return {.Fixed, value} }

// Padding is vertical, horizontal. Sizes are content-derived or fixed, bounded
// by the enclosing rect. Stretch affects content-sized children on the cross
// axis only; fixed cross sizes take precedence. No main-axis growth or shrink.
Layout_Style :: struct {
	flow: Layout_Flow,
	width, height: Layout_Size,
	padding: [2]f32,
	gap: f32,
	align: Text_Align,
	stretch: bool,
}

@(private) Layout_Node :: struct {parent, end, hit, text_command: int}
@(private) Layout_Measure :: struct {preferred, size: [2]f32, max_height: f32, text: Text_Layout}
@(private) Layout_Command_Kind :: enum {Paint, Text}
@(private) Layout_Command :: struct {
	kind: Layout_Command_Kind,
	node: int,
	color: Color,
	image: Image,
	corners: f32,
	font: Font,
	size, weight: f32,
	direction: Text_Direction,
	value_start, value_end, language_start, language_end: int,
}
@(private) Layout_Store :: struct {
	active: bool,
	direction: Direction,
	available: Rect,
	surface_start: int,
	nodes: [dynamic]Layout_Node,
	styles: [dynamic]Layout_Style,
	measure: [dynamic]Layout_Measure,
	bounds: [dynamic]Rect,
	stack: [dynamic]int,
	commands: [dynamic]Layout_Command,
	strings: [dynamic]u8,
}

// Start a local content-sized layout constrained by the current remaining rect.
// close_layout consumes its resolved extent along the requested cut direction.
// Nested boxes use open_box, not another open_layout.
open_layout :: proc{open_layout_implicit, open_layout_keyed}
@(private)
open_layout_implicit :: proc(direction: Direction, style: Layout_Style = {}, loc := #caller_location) {
	open_layout_key(direction, style, Identity_Key{location = loc})
}
@(private)
open_layout_keyed :: proc(direction: Direction, style: Layout_Style = {}, key: $T) where intrinsics.type_is_integer(T) {
	open_layout_key(direction, style, integer_identity_key(key))
}
@(private)
open_layout_key :: proc(direction: Direction, style: Layout_Style, key: Identity_Key) {
	area := current_rect() // Also rejects nesting unresolved layout roots.
	flush_surface_state()
	store := &active_state.layout
	clear(&store.nodes); clear(&store.styles); clear(&store.measure); clear(&store.bounds)
	clear(&store.stack); clear(&store.commands); clear(&store.strings)
	store.available, store.direction = area, direction
	store.surface_start = len(current_frame().surfaces)
	store.active = true
	layout_enter(style, key, .Layout_Root)
}

open_box :: proc{open_box_implicit, open_box_keyed}
@(private)
open_box_implicit :: proc(style: Layout_Style = {}, loc := #caller_location) {
	layout_enter(style, Identity_Key{location = loc}, .Layout_Box)
}
@(private)
open_box_keyed :: proc(style: Layout_Style = {}, key: $T) where intrinsics.type_is_integer(T) {
	layout_enter(style, integer_identity_key(key), .Layout_Box)
}
@(private)
layout_enter :: proc(style: Layout_Style, key: Identity_Key, kind: Identity_Scope_Kind) {
	store := &active_state.layout
	assert(store.active, "open_box needs a local layout")
	assert(valid_length(style.gap) && valid_length(style.padding.x) && valid_length(style.padding.y))
	assert(valid_length(style.width.value) && valid_length(style.height.value))
	parent := -1
	if len(store.stack) > 0 {
		parent = store.stack[len(store.stack) - 1]
	}
	id := identity_enter(key, kind)
	index := len(store.nodes)
	append(&store.nodes, Layout_Node{parent = parent, hit = register_hit(id, {}), text_command = -1})
	append(&store.styles, style)
	append(&store.measure, Layout_Measure{})
	append(&store.bounds, Rect{})
	append(&store.stack, index)
}

close_box :: proc() {
	store := &active_state.layout
	assert(store.active && len(store.stack) > 1, "Use close_layout for the root")
	identity_leave(.Layout_Box)
	index := pop(&store.stack)
	store.nodes[index].end = len(store.nodes)
}

// Text is a measured leaf and a deferred draw operation. Copy bytes now so
// callers can reuse a formatting buffer before the layout closes.
text_item :: proc(value: string, font: Font_Ref, size: f32 = 16, color: Color = {1, 1, 1, 1}, weight: f32 = 0, direction: Text_Direction = .Auto, language: string = "", loc := #caller_location) {
	open_box(loc = loc)
	store := &active_state.layout
	index := store.stack[len(store.stack) - 1]
	command := Layout_Command{kind = .Text, node = index, color = color,
		font = resolve_font(font), size = size, weight = weight, direction = direction}
	command.value_start = len(store.strings)
	append(&store.strings, ..transmute([]u8)value)
	command.value_end = len(store.strings)
	command.language_start = len(store.strings)
	append(&store.strings, ..transmute([]u8)language)
	command.language_end = len(store.strings)
	store.nodes[index].text_command = len(store.commands)
	append(&store.commands, command)
	close_box()
}

@(private)
layout_paint :: proc(color: Color, image: Image, corners: f32) {
	store := &active_state.layout
	append(&store.commands, Layout_Command{node = store.stack[len(store.stack) - 1], color = color, image = image, corners = corners})
}

// Resolves only recorded data: identities, input handlers and animations are
// never replayed. Returns the content bounds and first deferred text error.
// Cutting removes a full strip; these bounds need not fill its cross axis.
close_layout :: proc() -> (Rect, Text_Error) {
	store := &active_state.layout
	assert(store.active && len(store.stack) == 1, "Unclosed layout boxes")
	assert(len(current_frame().surfaces) == store.surface_start, "Direct surface appends are not supported inside unresolved layout")
	identity_leave(.Layout_Root)
	store.nodes[0].end = len(store.nodes)
	clear(&store.stack)
	err := layout_solve(store)
	root := store.available
	root.size = store.measure[0].size
	axis := 1 if store.direction == .Top || store.direction == .Bottom else 0
	if store.direction == .Bottom || store.direction == .Right {
		root.position[axis] += store.available.size[axis] - root.size[axis]
	}
	store.bounds[0] = root
	layout_place(store)
	store.active = false
	parent := current_rect_context()
	parent.remaining.size[axis] -= root.size[axis]
	if store.direction == .Top || store.direction == .Left { parent.remaining.position[axis] += root.size[axis] }
	for node, i in store.nodes { active_state.interaction.current[node.hit].bounds = store.bounds[i] }
	frame := current_frame()
	for command in store.commands {
		r := store.bounds[command.node]
		if command.kind == .Paint {
			append(&frame.surfaces, Surface{position = r.position, size = r.size,
				background = command.color, image = command.image, corner_radius = command.corners})
		} else if r.size.x > 0 && r.size.y > 0 && command.font != 0 {
			draw_err := fonts.draw_layout(&active_state.text, frame.renderer, store.measure[command.node].text,
				r.position, r.size, command.color, &frame.surfaces)
			if err == .None { err = draw_err }
		}
	}
	flush_surface_state()
	return root, err
}

@(private)
layout_text_measure :: proc(store: ^Layout_Store, command: Layout_Command, width: f32) -> (Text_Layout, Text_Error) {
	value := transmute(string)store.strings[command.value_start:command.value_end]
	language := transmute(string)store.strings[command.language_start:command.language_end]
	return fonts.layout(&active_state.text, command.font, value, command.size, current_frame().scale,
		command.weight, width, command.direction, language)
}

@(private)
layout_solve :: proc(store: ^Layout_Store) -> Text_Error {
	err := Text_Error.None
	// Bottom-up intrinsic widths (including explicit newlines in text).
	// Text uses signed 26.6 physical widths; stay within that range even at
	// high display scale, with headroom for f32 rounding.
	for i := len(store.nodes) - 1; i >= 0; i -= 1 {
		node, style := store.nodes[i], store.styles[i]
		preferred: [2]f32
		if node.text_command >= 0 {
			text, text_err := layout_text_measure(store, store.commands[node.text_command], (f32(max(i32)) - 256) / 64 / current_frame().scale)
			if err == .None { err = text_err }
			preferred = {text.width, text.height}
			store.measure[i].text = text
		} else {
			axis := 0 if style.flow == .Row else 1
			count := 0
			for c := i + 1; c < node.end; c = store.nodes[c].end {
				child := store.measure[c].preferred
				preferred[axis] += child[axis]
				preferred[1 - axis] = max(preferred[1 - axis], child[1 - axis])
				count += 1
			}
			preferred[axis] += f32(max(0, count - 1)) * style.gap
			preferred += [2]f32{style.padding.y, style.padding.x} * 2
		}
		if style.width.mode == .Fixed { preferred.x = style.width.value }
		if style.height.mode == .Fixed { preferred.y = style.height.value }
		store.measure[i].preferred = preferred
	}
	// Top-down constraints. Siblings each get the parent's inner bounds;
	// they do not compete for a share of remaining main-axis space. A row may
	// therefore overflow as a group even though each item is constrained.
	store.measure[0].size.x = min(store.measure[0].preferred.x, store.available.size.x)
	store.measure[0].max_height = store.available.size.y
	for node, i in store.nodes {
		style := store.styles[i]
		if style.height.mode == .Fixed {
			store.measure[i].max_height = min(store.measure[i].max_height, style.height.value)
		}
		width := max(0, store.measure[i].size.x - 2 * style.padding.y)
		height := max(0, store.measure[i].max_height - 2 * style.padding.x)
		for c := i + 1; c < node.end; c = store.nodes[c].end {
			w := min(store.measure[c].preferred.x, width)
			if style.flow == .Column && style.stretch && store.styles[c].width.mode == .Content { w = width }
			store.measure[c].size.x = w
			store.measure[c].max_height = height
		}
	}
	// Width-dependent text and bottom-up heights; no application-code replay.
	for i := len(store.nodes) - 1; i >= 0; i -= 1 {
		node, style := store.nodes[i], store.styles[i]
		height: f32
		if node.text_command >= 0 {
			// The intrinsic result already has the correct lines when it fits,
			// including explicit newlines. Only narrower bounds need rewrapping.
			text := store.measure[i].text
			if store.measure[i].size.x < text.width {
				measured, text_err := layout_text_measure(store, store.commands[node.text_command], store.measure[i].size.x)
				if err == .None { err = text_err }
				text = measured
				store.measure[i].text = text
			}
			height = text.height
		} else {
			count := 0
			for c := i + 1; c < node.end; c = store.nodes[c].end {
				if style.flow == .Row { height = max(height, store.measure[c].size.y) } else { height += store.measure[c].size.y }
				count += 1
			}
			if style.flow == .Column { height += f32(max(0, count - 1)) * style.gap }
			height += 2 * style.padding.x
		}
		if style.height.mode == .Fixed { height = style.height.value }
		store.measure[i].size.y = min(height, store.measure[i].max_height)
	}
	return err
}

@(private)
layout_place :: proc(store: ^Layout_Store) {
	for node, i in store.nodes {
		style, bounds := store.styles[i], store.bounds[i]
		axis := 0 if style.flow == .Row else 1
		inset := [2]f32{style.padding.y, style.padding.x}
		position := bounds.position + inset
		inner := bounds.size - inset * 2
		for c := i + 1; c < node.end; c = store.nodes[c].end {
			size := store.measure[c].size
			// Width stretch was resolved before text wrapping. Height stretch
			// follows final parent height, and propagates through nested rows.
			if style.flow == .Row && style.stretch && store.styles[c].height.mode == .Content {
				size.y = max(0, inner.y)
			}
			p := position
			space := max(0, inner[1 - axis] - size[1 - axis])
			if style.align == .Center { p[1 - axis] += space / 2 }
			if style.align == .End { p[1 - axis] += space }
			store.bounds[c] = Rect{p, size}
			position[axis] += size[axis] + style.gap
		}
	}
}

@(private)
destroy_layout :: proc(store: ^Layout_Store) {
	delete(store.nodes); delete(store.styles); delete(store.measure); delete(store.bounds)
	delete(store.stack); delete(store.commands); delete(store.strings)
}
