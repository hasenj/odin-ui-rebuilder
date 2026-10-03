// text-input-v3 version 1 ABI; generated from wayland-protocols XML.
package platform
/*
    Copyright © 2012, 2013 Intel Corporation
    Copyright © 2015, 2016 Jan Arne Petersen
    Copyright © 2017, 2018 Red Hat, Inc.
    Copyright © 2018       Purism SPC

    Permission to use, copy, modify, distribute, and sell this
    software and its documentation for any purpose is hereby granted
    without fee, provided that the above copyright notice appear in
    all copies and that both that copyright notice and this permission
    notice appear in supporting documentation, and that the name of
    the copyright holders not be used in advertising or publicity
    pertaining to distribution of the software without specific,
    written prior permission.  The copyright holders make no
    representations about the suitability of this software for any
    purpose.  It is provided "as is" without express or implied
    warranty.

    THE COPYRIGHT HOLDERS DISCLAIM ALL WARRANTIES WITH REGARD TO THIS
    SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
    FITNESS, IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
    SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
    WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
    AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
    ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
    THIS SOFTWARE.
  */
zwp_text_input_v3_interface: WL_Interface
zwp_text_input_v3_request_3_types := [?]^WL_Interface{nil, nil, nil}
zwp_text_input_v3_request_4_types := [?]^WL_Interface{nil}
zwp_text_input_v3_request_5_types := [?]^WL_Interface{nil, nil}
zwp_text_input_v3_request_6_types := [?]^WL_Interface{nil, nil, nil, nil}
zwp_text_input_v3_requests := [?]WL_Message{
	{"destroy", "", nil},
	{"enable", "", nil},
	{"disable", "", nil},
	{"set_surrounding_text", "sii", raw_data(zwp_text_input_v3_request_3_types[:])},
	{"set_text_change_cause", "u", raw_data(zwp_text_input_v3_request_4_types[:])},
	{"set_content_type", "uu", raw_data(zwp_text_input_v3_request_5_types[:])},
	{"set_cursor_rectangle", "iiii", raw_data(zwp_text_input_v3_request_6_types[:])},
	{"commit", "", nil},
}
zwp_text_input_v3_event_0_types := [?]^WL_Interface{&wl_surface_interface}
zwp_text_input_v3_event_1_types := [?]^WL_Interface{&wl_surface_interface}
zwp_text_input_v3_event_2_types := [?]^WL_Interface{nil, nil, nil}
zwp_text_input_v3_event_3_types := [?]^WL_Interface{nil}
zwp_text_input_v3_event_4_types := [?]^WL_Interface{nil, nil}
zwp_text_input_v3_event_5_types := [?]^WL_Interface{nil}
zwp_text_input_v3_events := [?]WL_Message{
	{"enter", "o", raw_data(zwp_text_input_v3_event_0_types[:])},
	{"leave", "o", raw_data(zwp_text_input_v3_event_1_types[:])},
	{"preedit_string", "?sii", raw_data(zwp_text_input_v3_event_2_types[:])},
	{"commit_string", "?s", raw_data(zwp_text_input_v3_event_3_types[:])},
	{"delete_surrounding_text", "uu", raw_data(zwp_text_input_v3_event_4_types[:])},
	{"done", "u", raw_data(zwp_text_input_v3_event_5_types[:])},
}
zwp_text_input_manager_v3_interface: WL_Interface
zwp_text_input_manager_v3_request_1_types := [?]^WL_Interface{&zwp_text_input_v3_interface, &wl_seat_interface}
zwp_text_input_manager_v3_requests := [?]WL_Message{
	{"destroy", "", nil},
	{"get_text_input", "no", raw_data(zwp_text_input_manager_v3_request_1_types[:])},
}
zwp_text_input_manager_v3_events: [0]WL_Message
@(private)
wayland_init_text_protocol :: proc() {
	zwp_text_input_v3_interface = {"zwp_text_input_v3", 1, i32(len(zwp_text_input_v3_requests)), raw_data(zwp_text_input_v3_requests[:]), i32(len(zwp_text_input_v3_events)), raw_data(zwp_text_input_v3_events[:])}
	zwp_text_input_manager_v3_interface = {"zwp_text_input_manager_v3", 1, i32(len(zwp_text_input_manager_v3_requests)), raw_data(zwp_text_input_manager_v3_requests[:]), i32(len(zwp_text_input_manager_v3_events)), raw_data(zwp_text_input_manager_v3_events[:])}
}
