#!/usr/bin/env python3
"""Native input/clipboard smoke check for a live Hyprland session.

Build tests/wayland_input as bin/wayland-input-check first. Requires hyprctl
and wl-clipboard. Only the test window receives injected shortcuts. Preserve
and restore the desktop's text clipboard; non-text selections are not supported.
"""
import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    previous = subprocess.run(["wl-paste", "--no-newline", "--type", "text"], capture_output=True)
    if previous.returncode != 0:
        types = subprocess.run(["wl-paste", "--list-types"], capture_output=True)
        if types.returncode == 0 and types.stdout.strip():
            raise RuntimeError("Clipboard contains non-text data; cannot preserve it for this test")
    process = subprocess.Popen(
        [str(ROOT / "bin/wayland-input-check")], cwd=ROOT,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    try:
        address = panel_address = None
        for _ in range(200):
            clients = json.loads(subprocess.check_output(["hyprctl", "clients", "-j"]))
            address = next((c["address"] for c in clients if c["pid"] == process.pid and c["title"] == "Wayland native text check"), None)
            panel_address = next((c["address"] for c in clients if c["pid"] == process.pid and c["title"] == "Wayland native panel check"), None)
            if address and panel_address:
                break
            if process.poll() is not None:
                raise RuntimeError(process.stdout.read())
            time.sleep(0.05)
        if not address or not panel_address:
            raise RuntimeError("Test window did not map")
        target = "address:" + panel_address
        run("hyprctl", "dispatch", f"hl.dsp.focus({{window = {json.dumps(target)}}})", stdout=subprocess.DEVNULL)
        time.sleep(0.2)

        def key(modifiers, name):
            for state in ("down", "up"):
                expression = ("hl.dsp.send_key_state({" + f"mods = {json.dumps(modifiers)}, key = {json.dumps(name)}, "
                              + f"state = {json.dumps(state)}, window = {json.dumps(target)}" + "})")
                run("hyprctl", "dispatch", expression, stdout=subprocess.DEVNULL)
                time.sleep(0.05)
            time.sleep(0.1)

        key("", "p")
        target = "address:" + address
        run("hyprctl", "dispatch", f"hl.dsp.focus({{window = {json.dumps(target)}}})", stdout=subprocess.DEVNULL)
        time.sleep(0.2)
        key("", "a")
        key("", "b")
        key("CTRL", "a")
        key("CTRL", "c")
        copied = subprocess.check_output(["wl-paste", "--no-newline", "--type", "text/plain;charset=utf-8"], timeout=5)
        assert copied == b"ab", copied
        key("", "c")
        key("CTRL", "v")  # Paste our own selection without a pipe deadlock.
        run("wl-copy", "--type", "text/plain;charset=utf-8", input="外".encode())
        time.sleep(0.15)
        key("CTRL", "v")  # Receive another client's UTF-8 selection.
        key("", "Return")
        output = process.communicate(timeout=15)[0]
        print(output, end="")
        assert process.returncode == 0, process.returncode
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait()
        if previous.returncode == 0:
            run("wl-copy", input=previous.stdout)
        else:
            run("wl-copy", "--clear")


if __name__ == "__main__":
    main()
