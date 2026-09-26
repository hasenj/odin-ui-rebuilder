// Shared input data, written by the platform before the application update.
package input

State :: struct {
	// Logical points relative to the content area's top left, with Y down.
	// Position continues updating outside the content area and is not clamped.
	mouse_position: [2]f32,
	// Geometric containment in the content area, not an occlusion/focus test.
	mouse_inside: bool,
}
