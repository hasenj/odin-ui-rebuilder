// Wayland ABI and xdg-shell/xdg-decoration v1 metadata.
// Protocol definitions: https://gitlab.freedesktop.org/wayland/wayland-protocols
// Only version 1 of the extension protocols is negotiated.
package platform

/*
Copyright © 2008-2013 Kristian Høgsberg
    Copyright © 2013      Rafael Antognolli
    Copyright © 2013      Jasper St. Pierre
    Copyright © 2010-2013 Intel Corporation
    Copyright © 2015-2017 Samsung Electronics Co., Ltd
    Copyright © 2015-2017 Red Hat Inc.

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice (including the next
    paragraph) shall be included in all copies or substantial portions of the
    Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
    THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
*/
xdg_wm_base_request_1_types := [?]^WL_Interface{&xdg_positioner_interface}
xdg_wm_base_request_2_types := [?]^WL_Interface{&xdg_surface_interface, &wl_surface_interface}
xdg_wm_base_request_3_types := [?]^WL_Interface{nil}
xdg_wm_base_requests := [?]WL_Message{
	{"destroy", "", nil},
	{"create_positioner", "n", raw_data(xdg_wm_base_request_1_types[:])},
	{"get_xdg_surface", "no", raw_data(xdg_wm_base_request_2_types[:])},
	{"pong", "u", raw_data(xdg_wm_base_request_3_types[:])},
}
xdg_wm_base_event_0_types := [?]^WL_Interface{nil}
xdg_wm_base_events := [?]WL_Message{
	{"ping", "u", raw_data(xdg_wm_base_event_0_types[:])},
}
xdg_wm_base_interface: WL_Interface
xdg_positioner_request_1_types := [?]^WL_Interface{nil, nil}
xdg_positioner_request_2_types := [?]^WL_Interface{nil, nil, nil, nil}
xdg_positioner_request_3_types := [?]^WL_Interface{nil}
xdg_positioner_request_4_types := [?]^WL_Interface{nil}
xdg_positioner_request_5_types := [?]^WL_Interface{nil}
xdg_positioner_request_6_types := [?]^WL_Interface{nil, nil}
xdg_positioner_requests := [?]WL_Message{
	{"destroy", "", nil},
	{"set_size", "ii", raw_data(xdg_positioner_request_1_types[:])},
	{"set_anchor_rect", "iiii", raw_data(xdg_positioner_request_2_types[:])},
	{"set_anchor", "u", raw_data(xdg_positioner_request_3_types[:])},
	{"set_gravity", "u", raw_data(xdg_positioner_request_4_types[:])},
	{"set_constraint_adjustment", "u", raw_data(xdg_positioner_request_5_types[:])},
	{"set_offset", "ii", raw_data(xdg_positioner_request_6_types[:])},
}
xdg_positioner_events := [?]WL_Message{
}
xdg_positioner_interface: WL_Interface
xdg_surface_request_1_types := [?]^WL_Interface{&xdg_toplevel_interface}
xdg_surface_request_2_types := [?]^WL_Interface{&xdg_popup_interface, &xdg_surface_interface, &xdg_positioner_interface}
xdg_surface_request_3_types := [?]^WL_Interface{nil, nil, nil, nil}
xdg_surface_request_4_types := [?]^WL_Interface{nil}
xdg_surface_requests := [?]WL_Message{
	{"destroy", "", nil},
	{"get_toplevel", "n", raw_data(xdg_surface_request_1_types[:])},
	{"get_popup", "n?oo", raw_data(xdg_surface_request_2_types[:])},
	{"set_window_geometry", "iiii", raw_data(xdg_surface_request_3_types[:])},
	{"ack_configure", "u", raw_data(xdg_surface_request_4_types[:])},
}
xdg_surface_event_0_types := [?]^WL_Interface{nil}
xdg_surface_events := [?]WL_Message{
	{"configure", "u", raw_data(xdg_surface_event_0_types[:])},
}
xdg_surface_interface: WL_Interface
xdg_toplevel_request_1_types := [?]^WL_Interface{&xdg_toplevel_interface}
xdg_toplevel_request_2_types := [?]^WL_Interface{nil}
xdg_toplevel_request_3_types := [?]^WL_Interface{nil}
xdg_toplevel_request_4_types := [?]^WL_Interface{&wl_seat_interface, nil, nil, nil}
xdg_toplevel_request_5_types := [?]^WL_Interface{&wl_seat_interface, nil}
xdg_toplevel_request_6_types := [?]^WL_Interface{&wl_seat_interface, nil, nil}
xdg_toplevel_request_7_types := [?]^WL_Interface{nil, nil}
xdg_toplevel_request_8_types := [?]^WL_Interface{nil, nil}
xdg_toplevel_request_11_types := [?]^WL_Interface{&wl_output_interface}
xdg_toplevel_requests := [?]WL_Message{
	{"destroy", "", nil},
	{"set_parent", "?o", raw_data(xdg_toplevel_request_1_types[:])},
	{"set_title", "s", raw_data(xdg_toplevel_request_2_types[:])},
	{"set_app_id", "s", raw_data(xdg_toplevel_request_3_types[:])},
	{"show_window_menu", "ouii", raw_data(xdg_toplevel_request_4_types[:])},
	{"move", "ou", raw_data(xdg_toplevel_request_5_types[:])},
	{"resize", "ouu", raw_data(xdg_toplevel_request_6_types[:])},
	{"set_max_size", "ii", raw_data(xdg_toplevel_request_7_types[:])},
	{"set_min_size", "ii", raw_data(xdg_toplevel_request_8_types[:])},
	{"set_maximized", "", nil},
	{"unset_maximized", "", nil},
	{"set_fullscreen", "?o", raw_data(xdg_toplevel_request_11_types[:])},
	{"unset_fullscreen", "", nil},
	{"set_minimized", "", nil},
}
xdg_toplevel_event_0_types := [?]^WL_Interface{nil, nil, nil}
xdg_toplevel_events := [?]WL_Message{
	{"configure", "iia", raw_data(xdg_toplevel_event_0_types[:])},
	{"close", "", nil},
}
xdg_toplevel_interface: WL_Interface
xdg_popup_request_1_types := [?]^WL_Interface{&wl_seat_interface, nil}
xdg_popup_requests := [?]WL_Message{
	{"destroy", "", nil},
	{"grab", "ou", raw_data(xdg_popup_request_1_types[:])},
}
xdg_popup_event_0_types := [?]^WL_Interface{nil, nil, nil, nil}
xdg_popup_events := [?]WL_Message{
	{"configure", "iiii", raw_data(xdg_popup_event_0_types[:])},
	{"popup_done", "", nil},
}
xdg_popup_interface: WL_Interface

/*
Copyright © 2018 Simon Ser

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice (including the next
    paragraph) shall be included in all copies or substantial portions of the
    Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
    THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
*/
zxdg_decoration_manager_v1_request_1_types := [?]^WL_Interface{&zxdg_toplevel_decoration_v1_interface, &xdg_toplevel_interface}
zxdg_decoration_manager_v1_requests := [?]WL_Message{
	{"destroy", "", nil},
	{"get_toplevel_decoration", "no", raw_data(zxdg_decoration_manager_v1_request_1_types[:])},
}
zxdg_decoration_manager_v1_events := [?]WL_Message{
}
zxdg_decoration_manager_v1_interface: WL_Interface
zxdg_toplevel_decoration_v1_request_1_types := [?]^WL_Interface{nil}
zxdg_toplevel_decoration_v1_requests := [?]WL_Message{
	{"destroy", "", nil},
	{"set_mode", "u", raw_data(zxdg_toplevel_decoration_v1_request_1_types[:])},
	{"unset_mode", "", nil},
}
zxdg_toplevel_decoration_v1_event_0_types := [?]^WL_Interface{nil}
zxdg_toplevel_decoration_v1_events := [?]WL_Message{
	{"configure", "u", raw_data(zxdg_toplevel_decoration_v1_event_0_types[:])},
}
zxdg_toplevel_decoration_v1_interface: WL_Interface

@(private)
wayland_init_protocols :: proc() {
	wayland_init_text_protocol()
	xdg_wm_base_interface = {"xdg_wm_base", 1, i32(len(xdg_wm_base_requests)), raw_data(xdg_wm_base_requests[:]), i32(len(xdg_wm_base_events)), raw_data(xdg_wm_base_events[:])}
	xdg_positioner_interface = {"xdg_positioner", 1, i32(len(xdg_positioner_requests)), raw_data(xdg_positioner_requests[:]), i32(len(xdg_positioner_events)), raw_data(xdg_positioner_events[:])}
	xdg_surface_interface = {"xdg_surface", 1, i32(len(xdg_surface_requests)), raw_data(xdg_surface_requests[:]), i32(len(xdg_surface_events)), raw_data(xdg_surface_events[:])}
	xdg_toplevel_interface = {"xdg_toplevel", 1, i32(len(xdg_toplevel_requests)), raw_data(xdg_toplevel_requests[:]), i32(len(xdg_toplevel_events)), raw_data(xdg_toplevel_events[:])}
	xdg_popup_interface = {"xdg_popup", 1, i32(len(xdg_popup_requests)), raw_data(xdg_popup_requests[:]), i32(len(xdg_popup_events)), raw_data(xdg_popup_events[:])}
	zxdg_decoration_manager_v1_interface = {"zxdg_decoration_manager_v1", 1, i32(len(zxdg_decoration_manager_v1_requests)), raw_data(zxdg_decoration_manager_v1_requests[:]), i32(len(zxdg_decoration_manager_v1_events)), raw_data(zxdg_decoration_manager_v1_events[:])}
	zxdg_toplevel_decoration_v1_interface = {"zxdg_toplevel_decoration_v1", 1, i32(len(zxdg_toplevel_decoration_v1_requests)), raw_data(zxdg_toplevel_decoration_v1_requests[:]), i32(len(zxdg_toplevel_decoration_v1_events)), raw_data(zxdg_toplevel_decoration_v1_events[:])}
}
