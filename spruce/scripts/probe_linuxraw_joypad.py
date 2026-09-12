#!/usr/bin/env python3
"""
Probe the legacy joydev (/dev/input/js*) button and axis numbering.

Why this exists: RetroArch enumerates the same physical pad differently in
every input driver. The udev profile's indices are not the sdl2 profile's, and
neither is the linuxraw profile's - linuxraw talks to the legacy joydev API,
which numbers buttons in kernel registration order. So the only reliable way to
write a linuxraw autoconfig is to read the numbers off the device.

linuxraw matters on BaseOS because it needs no udev and no SDL: RetroArch's
udev joypad driver enumerates nothing where no udevd runs, and the stock 32-bit
SDL2 dlopens libudev, so it hits the same wall.

Run it on the device, follow the prompts, and send back everything it prints.
It only reads - it opens no display and changes no state.

    /mnt/SDCARD/spruce/flip/bin/python3.10 /mnt/SDCARD/spruce/scripts/probe_linuxraw_joypad.py

If js0 is not the right node, pass another: ... probe_linuxraw_joypad.py /dev/input/js1
"""

import fcntl
import os
import struct
import sys

# linux/joystick.h. _IOC(dir=READ, type='j', nr, size) packed as
# (dir << 30) | (size << 16) | (type << 8) | nr
JSIOCGAXES = 0x80016A11     # __u8  number of axes
JSIOCGBUTTONS = 0x80016A12  # __u8  number of buttons
JSIOCGNAME = 0x80806A13     # char[128] device name

# js_event: __u32 time, __s16 value, __u8 type, __u8 number
JS_EVENT = "IhBB"
JS_EVENT_SIZE = struct.calcsize(JS_EVENT)
JS_EVENT_BUTTON = 0x01
JS_EVENT_AXIS = 0x02
JS_EVENT_INIT = 0x80

# Order matters only in that you press them in the order printed.
BUTTON_PROMPTS = [
    "A (East / right face button)",
    "B (South / bottom face button)",
    "X (North / top face button)",
    "Y (West / left face button)",
    "L1",
    "R1",
    "L2",
    "R2",
    "Select",
    "Start",
    "L3 (click the left stick) - or press Start again to skip",
    "R3 (click the right stick) - or press Start again to skip",
]

AXIS_PROMPTS = [
    "LEFT stick fully RIGHT, then centre it",
    "LEFT stick fully DOWN, then centre it",
    "RIGHT stick fully RIGHT, then centre it  - or skip with any button",
    "RIGHT stick fully DOWN, then centre it   - or skip with any button",
    "D-pad RIGHT, then release",
    "D-pad DOWN, then release",
]


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "/dev/input/js0"

    if not os.path.exists(path):
        print("ERROR: %s does not exist." % path)
        print("Available:", sorted(p for p in os.listdir("/dev/input") if p.startswith("js")) or "none")
        print("If there are no js* nodes at all, the joydev module is not loaded")
        print("and the linuxraw driver is not an option on this build.")
        return 1

    fd = os.open(path, os.O_RDONLY)

    name = bytearray(128)
    try:
        fcntl.ioctl(fd, JSIOCGNAME, name)
        devname = name.split(b"\0", 1)[0].decode("utf-8", "replace")
    except OSError:
        devname = "(JSIOCGNAME failed)"

    axes = bytearray(1)
    buttons = bytearray(1)
    try:
        fcntl.ioctl(fd, JSIOCGAXES, axes)
        fcntl.ioctl(fd, JSIOCGBUTTONS, buttons)
    except OSError:
        axes[0] = buttons[0] = 0

    print("=" * 62)
    print("node        : %s" % path)
    print("device name : %s" % devname)
    print("axes        : %d" % axes[0])
    print("buttons     : %d" % buttons[0])
    print("=" * 62)
    print("input_device in the autoconfig must match the device name above.")
    print()

    # The kernel replays current state on open with JS_EVENT_INIT set. Drain it
    # so those synthetic events are not mistaken for presses.
    os.set_blocking(fd, False)
    while True:
        try:
            if not os.read(fd, JS_EVENT_SIZE):
                break
        except BlockingIOError:
            break
    os.set_blocking(fd, True)

    def next_event(kinds):
        """Block until a real (non-init) event of one of `kinds` arrives."""
        while True:
            data = os.read(fd, JS_EVENT_SIZE)
            if len(data) < JS_EVENT_SIZE:
                continue
            _, value, etype, number = struct.unpack(JS_EVENT, data)
            if etype & JS_EVENT_INIT:
                continue
            etype &= ~JS_EVENT_INIT
            if etype in kinds:
                return etype, number, value

    print("--- BUTTONS ---  press each one once")
    button_map = {}
    for label in BUTTON_PROMPTS:
        print("  press: %-46s" % label, end="", flush=True)
        etype, number, value = next_event({JS_EVENT_BUTTON})
        while value == 0:  # wait for the press, not the release
            etype, number, value = next_event({JS_EVENT_BUTTON})
        print(" -> button %d" % number)
        button_map[label] = number
        # swallow the matching release so it does not answer the next prompt
        while True:
            etype, n2, v2 = next_event({JS_EVENT_BUTTON})
            if v2 == 0 and n2 == number:
                break

    print()
    print("--- AXES ---  move each one; a large value identifies it")
    axis_map = {}
    for label in AXIS_PROMPTS:
        print("  move : %-46s" % label, end="", flush=True)
        while True:
            etype, number, value = next_event({JS_EVENT_AXIS, JS_EVENT_BUTTON})
            if etype == JS_EVENT_BUTTON:
                print(" -> skipped")
                break
            if abs(value) > 16000:
                print(" -> axis %d (value %d)" % (number, value))
                axis_map[label] = (number, value)
                break

    print()
    print("=" * 62)
    print("SUMMARY - send all of this back")
    print("=" * 62)
    print("device name : %s" % devname)
    print("axes=%d buttons=%d" % (axes[0], buttons[0]))
    for label, number in button_map.items():
        print("  %-46s button %d" % (label, number))
    for label, (number, value) in axis_map.items():
        print("  %-46s axis %d (%d)" % (label, number, value))

    os.close(fd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
