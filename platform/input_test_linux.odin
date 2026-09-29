#+build linux
package platform

import "core:testing"

// Exercise the negotiated wl_pointer v5 callback pipeline without a compositor.
@(test)
wayland_wheel_snapshots :: proc(t: ^testing.T) {
	w := Wayland_Window{odin_context = context, pointer_focused = true}
	pointer_axis(&w, nil, 0, 0, 20 * 256)
	pointer_axis(&w, nil, 0, 1, -4 * 256)
	pointer_axis_discrete(&w, nil, 0, 1)
	testing.expect(t, w.input.scroll_delta == [2]f32{})
	pointer_frame(&w, nil)
	pointer_axis(&w, nil, 0, 0, 128)
	pointer_frame(&w, nil)
	snapshot := take_wayland_input(&w)
	testing.expect(t, snapshot.scroll_delta == [2]f32{-4, 20.5})
	testing.expect(t, take_wayland_input(&w).scroll_delta == [2]f32{})
	pointer_axis(&w, nil, 0, 0, 256)
	pointer_leave(&w, nil, 0, nil)
	pointer_frame(&w, nil)
	pointer_axis(&w, nil, 0, 0, 256)
	pointer_frame(&w, nil)
	testing.expect(t, take_wayland_input(&w).scroll_delta == [2]f32{}, "Pointer leave must clear and reject pending scroll")
}
