package windows_test

import ui "../../core"

start_native_checks :: proc() {}
stop_native_checks :: proc() {}
check_native_frame :: proc(index: int) {}
native_checks_complete :: proc() -> bool { return true }
close_replacement :: proc() { ui.close_panel(ui.current_window()) }
close_main :: proc() { ui.request_close(ui.current_window()) }
quit_application :: proc() { ui.request_close(ui.current_window()) }
