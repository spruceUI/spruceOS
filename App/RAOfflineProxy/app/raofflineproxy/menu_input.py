from __future__ import annotations

import os
import select
import struct
from pathlib import Path

EVENT_SIZE = struct.calcsize("llHHi")
EV_KEY = 0x01
EV_ABS = 0x03
ABS_HAT0X = 16
ABS_HAT0Y = 17
KEY_UP = 103
KEY_DOWN = 108
KEY_LEFT = 105
KEY_RIGHT = 106
KEY_ENTER = 28
KEY_SPACE = 57
KEY_ESC = 1
KEY_BACKSPACE = 14
KEY_Q = 16
KEY_S = 31
BTN_SOUTH = 304
BTN_EAST = 305
BTN_TL = 308
BTN_TR = 309
BTN_SELECT = 314
BTN_START = 315
BTN_DPAD_UP = 544
BTN_DPAD_DOWN = 545
BTN_DPAD_LEFT = 546
BTN_DPAD_RIGHT = 547
INPUT_DIR = Path("/dev/input")


def open_input_devices() -> list[object]:
    handles: list[object] = []
    if not INPUT_DIR.exists():
        return handles

    for path in sorted(INPUT_DIR.glob("event*")):
        try:
            handle = open(path, "rb", buffering=0)
            os.set_blocking(handle.fileno(), False)
        except OSError:
            continue
        handles.append(handle)
    return handles


def close_input_devices(handles: list[object]) -> None:
    for handle in handles:
        try:
            handle.close()
        except OSError:
            pass



# Onion's gpio-keys-polled hardware has been observed producing a second
# full press/release cycle ~120-220ms after the first for a single physical
# tap (measured via kernel event timestamps on an isolated single-tap
# capture) -- a real switch-quality issue the kernel's own debounce config
# isn't filtering, not something a userspace timing window can fully
# separate from a fast deliberate repeat. This value is a tuned compromise
# between the two; raise it if double-navigates are still seen, lower it if
# rapid navigation feels throttled.
DEBOUNCE_SECONDS = 0.08


def read_keys(handles: list[object], last_press: dict[int, float] | None = None) -> list[int]:
    """Reads pending key events, emitting each code at most once per
    DEBOUNCE_SECONDS.

    Onion's gpio-keys-polled driver reports switch chatter as full,
    legitimate-looking press/release cycles (not just a stuck-down repeat) —
    a single physical tap has been observed producing several such cycles
    tens to hundreds of milliseconds apart. A press/release state machine
    can't tell that apart from genuine rapid presses, so this instead
    suppresses same-code presses that land within DEBOUNCE_SECONDS of the
    last accepted one, keyed off each event's own kernel timestamp (so it's
    unaffected by how long read_keys() itself takes to run). Pass the same
    dict across calls to debounce across calls; omit it to only debounce
    within a single call.
    """
    if not handles:
        return []

    last = last_press if last_press is not None else {}
    keys: list[int] = []
    readable, _, _ = select.select(handles, [], [], 0)
    for handle in readable:
        while True:
            try:
                event = handle.read(EVENT_SIZE)
            except BlockingIOError:
                break
            except OSError:
                break
            if event is None:
                break
            if len(event) != EVENT_SIZE:
                break

            seconds, micros, event_type, code, value = struct.unpack("llHHi", event)
            timestamp = seconds + micros / 1_000_000
            if event_type == EV_KEY:
                if value == 1:
                    _emit_debounced(keys, last, code, timestamp)
                continue
            if event_type == EV_ABS:
                if code == ABS_HAT0Y:
                    if value < 0:
                        _emit_debounced(keys, last, BTN_DPAD_UP, timestamp)
                    elif value > 0:
                        _emit_debounced(keys, last, BTN_DPAD_DOWN, timestamp)
                if code == ABS_HAT0X:
                    if value < 0:
                        _emit_debounced(keys, last, BTN_DPAD_LEFT, timestamp)
                    elif value > 0:
                        _emit_debounced(keys, last, BTN_DPAD_RIGHT, timestamp)
    return keys


def _emit_debounced(keys: list[int], last: dict[int, float], code: int, timestamp: float) -> None:
    previous = last.get(code)
    if previous is not None and timestamp - previous < DEBOUNCE_SECONDS:
        return
    last[code] = timestamp
    keys.append(code)
