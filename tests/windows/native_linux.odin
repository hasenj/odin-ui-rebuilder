package windows_test

import ui "../../core"

// Compositor frame callbacks drive the real GLES windows on Linux.
start_native_checks :: proc() {}
stop_native_checks :: proc() {}
check_native_frame :: proc(index: int) {}
native_checks_complete :: proc() -> bool { return true }

close_replacement :: proc() { ui.request_close(ui.current_window()) }
quit_application :: proc() { ui.request_close(ui.current_window()) }
