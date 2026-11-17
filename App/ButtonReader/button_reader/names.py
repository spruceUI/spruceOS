"""Kernel code names, the cfg's B_* / STICK_* values and PyUI's names. A control is (EV_KEY, code, 1)
for a key, or (EV_ABS, code, +1 or -1) for a hat direction or a trigger pushed that way.
"""
import os

EV_SYN = 0
EV_KEY = 1
EV_ABS = 3
EV_SW = 5

KEY_NAMES = {
    1: "KEY_ESC", 14: "KEY_BACKSPACE", 15: "KEY_TAB", 18: "KEY_E", 20: "KEY_T", 28: "KEY_ENTER",
    29: "KEY_LEFTCTRL", 42: "KEY_LEFTSHIFT", 54: "KEY_RIGHTSHIFT", 56: "KEY_LEFTALT", 57: "KEY_SPACE",
    97: "KEY_RIGHTCTRL", 100: "KEY_RIGHTALT", 102: "KEY_HOME", 103: "KEY_UP", 105: "KEY_LEFT",
    106: "KEY_RIGHT", 108: "KEY_DOWN", 113: "KEY_MUTE", 114: "KEY_VOLUMEDOWN", 115: "KEY_VOLUMEUP",
    116: "KEY_POWER", 139: "KEY_MENU", 142: "KEY_SLEEP", 143: "KEY_WAKEUP", 158: "KEY_BACK",
    172: "KEY_HOMEPAGE", 288: "BTN_TRIGGER", 289: "BTN_THUMB", 290: "BTN_THUMB2", 291: "BTN_TOP",
    292: "BTN_TOP2", 293: "BTN_PINKIE", 294: "BTN_BASE", 295: "BTN_BASE2", 296: "BTN_BASE3",
    297: "BTN_BASE4", 298: "BTN_BASE5", 299: "BTN_BASE6", 304: "BTN_SOUTH", 305: "BTN_EAST",
    306: "BTN_C", 307: "BTN_NORTH", 308: "BTN_WEST", 309: "BTN_Z", 310: "BTN_TL", 311: "BTN_TR",
    312: "BTN_TL2", 313: "BTN_TR2", 314: "BTN_SELECT", 315: "BTN_START", 316: "BTN_MODE",
    317: "BTN_THUMBL", 318: "BTN_THUMBR", 330: "BTN_TOUCH", 544: "BTN_DPAD_UP",
    545: "BTN_DPAD_DOWN", 546: "BTN_DPAD_LEFT", 547: "BTN_DPAD_RIGHT",
}
for _i in range(40):
    KEY_NAMES.setdefault(704 + _i, f"BTN_TRIGGER_HAPPY{_i + 1}")
ABS_NAMES = {0: "ABS_X", 1: "ABS_Y", 2: "ABS_Z", 3: "ABS_RX", 4: "ABS_RY", 5: "ABS_RZ",
             6: "ABS_THROTTLE", 7: "ABS_RUDDER", 8: "ABS_WHEEL", 9: "ABS_GAS", 10: "ABS_BRAKE",
             16: "ABS_HAT0X", 17: "ABS_HAT0Y", 18: "ABS_HAT1X", 19: "ABS_HAT1Y", 20: "ABS_HAT2X",
             21: "ABS_HAT2Y", 22: "ABS_HAT3X", 23: "ABS_HAT3Y", 40: "ABS_MISC", 47: "ABS_MT_SLOT",
             53: "ABS_MT_POSITION_X", 54: "ABS_MT_POSITION_Y", 57: "ABS_MT_TRACKING_ID"}
SW_NAMES = {0: "SW_LID", 2: "SW_HEADPHONE_INSERT", 4: "SW_MICROPHONE_INSERT", 6: "SW_LINEOUT_INSERT"}
HAT_FIRST = 16
HAT_LAST = 23
KEY_POWER = 116

# Picture slots: (slot, cfg variable, PyUI ControllerInput). The cfg names positions (A right,
# B bottom, X top, Y left), so a face slot follows the cfg and its label follows PyUI.
SLOTS = [
    ("BOTTOM", "B_B", "B"), ("RIGHT", "B_A", "A"), ("TOP", "B_X", "X"), ("LEFT", "B_Y", "Y"),
    ("DPAD_UP", "B_UP", "DPAD_UP"), ("DPAD_DOWN", "B_DOWN", "DPAD_DOWN"),
    ("DPAD_LEFT", "B_LEFT", "DPAD_LEFT"), ("DPAD_RIGHT", "B_RIGHT", "DPAD_RIGHT"),
    ("L1", "B_L1", "L1"), ("R1", "B_R1", "R1"), ("L2", "B_L2", "L2"), ("R2", "B_R2", "R2"),
    ("L3", "B_L3", "L3"), ("R3", "B_R3", "R3"), ("SELECT", "B_SELECT", "SELECT"),
    ("START", "B_START", "START"), ("MENU", "B_MENU", "MENU"), ("HOME", "B_HOME", "HOME"),
    ("VOL_UP", "B_VOLUP", "VOLUME_UP"), ("VOL_DOWN", "B_VOLDOWN", "VOLUME_DOWN"),
    ("POWER", "B_POWER", "POWER_BUTTON"),
]
SLOT_VAR = {slot: var for slot, var, _ in SLOTS}
PYUI_SLOT = {pyui: slot for slot, _, pyui in SLOTS}
LABELS = {"A": "A", "B": "B", "X": "X", "Y": "Y", "DPAD_UP": "Up", "DPAD_DOWN": "Down",
          "DPAD_LEFT": "Left", "DPAD_RIGHT": "Right", "L1": "L1", "R1": "R1", "L2": "L2",
          "R2": "R2", "L3": "L3", "R3": "R3", "SELECT": "Select", "START": "Start", "MENU": "Menu",
          "HOME": "Home", "VOLUME_UP": "Vol+", "VOLUME_DOWN": "Vol-", "POWER_BUTTON": "Power"}
# The letter printed at each face position: Nintendo unless the device's manifest says "xbox";
# the codes and the cfg stay by position either way.
FACE_DIRECTION = {"BOTTOM": "SOUTH", "RIGHT": "EAST", "TOP": "NORTH", "LEFT": "WEST"}
FACE_PRINT = {"nintendo": {"BOTTOM": "B", "RIGHT": "A", "TOP": "X", "LEFT": "Y"},
              "xbox": {"BOTTOM": "A", "RIGHT": "B", "TOP": "Y", "LEFT": "X"}}
# (stick, cfg variable for right, cfg variable for down, default X axis, default Y axis)
STICKS = [("LEFT", "STICK_RIGHT", "STICK_DOWN", 0, 1), ("RIGHT", "STICK_RIGHT_2", "STICK_DOWN_2", 3, 4)]
PYUI_STICK = {"LEFT_STICK_LEFT": ("LEFT", "x", -1), "LEFT_STICK_RIGHT": ("LEFT", "x", 1),
              "LEFT_STICK_UP": ("LEFT", "y", -1), "LEFT_STICK_DOWN": ("LEFT", "y", 1),
              "RIGHT_STICK_LEFT": ("RIGHT", "x", -1), "RIGHT_STICK_RIGHT": ("RIGHT", "x", 1),
              "RIGHT_STICK_UP": ("RIGHT", "y", -1), "RIGHT_STICK_DOWN": ("RIGHT", "y", 1)}
ABSENT = "absent"  # the cfg says DOESNT_EXIST


def key_name(code):
    return KEY_NAMES.get(code, f"KEY_{code}")


def abs_name(code):
    return ABS_NAMES.get(code, f"ABS_{code}")


def control_name(control):
    etype, code, sign = control
    if etype == EV_KEY:
        return key_name(code)
    return f"{abs_name(code)}{'+' if sign > 0 else '-'}"


def face_print_text(style):
    """'nintendo print: B bottom, A right, X top, Y left'."""
    letters = FACE_PRINT.get(style, FACE_PRINT["nintendo"])
    return f"{style} print: " + ", ".join(f"{letters[s]} {s.lower()}" for s in FACE_DIRECTION)


def face_prompt(slot, style):
    """'Press FACE_NORTH/X': the position, then the letter this device prints there."""
    return f"Press FACE_{FACE_DIRECTION[slot]}/{FACE_PRINT.get(style, FACE_PRINT['nintendo'])[slot]}"


def signed(value):
    """Values read with PyUI's unsigned 'llHHI' format come back as 2**32 - n."""
    return value - (1 << 32) if value >= (1 << 31) else value


def sign(value):
    return 1 if value > 0 else -1 if value < 0 else 0


def parse_spec(raw):
    """A cfg value: "1 305" -> (1, 305, None), "3 17 -1" -> (3, 17, -1); ABSENT; None if unusable."""
    if raw is None:
        return None
    raw = raw.strip()
    if raw == "DOESNT_EXIST":
        return ABSENT
    parts = raw.split()
    try:
        numbers = [int(p) for p in parts]
    except ValueError:
        return None
    if len(numbers) == 2:
        return numbers[0], numbers[1], None
    if len(numbers) == 3:
        return tuple(numbers)
    return None


def cfg_spec(var, env=None):
    return parse_spec((os.environ if env is None else env).get(var))


def spec_control(spec):
    """The control a button's cfg value names: a key, a hat direction or a trigger push."""
    if spec in (None, ABSENT):
        return None
    etype, code, value = spec
    if etype == EV_KEY:
        return EV_KEY, code, 1
    if etype == EV_ABS:
        return EV_ABS, code, sign(value) if value else 1
    return None


def stick_axis(spec):
    """(axis, +1 or -1) from STICK_RIGHT / STICK_DOWN: the axis and the sign of that direction."""
    if spec in (None, ABSENT) or spec[0] != EV_ABS:
        return None
    return spec[1], (sign(spec[2]) or 1) if spec[2] else 1


class Names:
    """Which slot, label, cfg variable and PyUI name each control has on this device."""

    def __init__(self, env=None, pyui_controls=None, pyui_sticks=None, manifest=None):
        env = os.environ if env is None else env
        self.env = env
        self.pyui = dict(pyui_controls or {})   # control -> ControllerInput name
        self.pyui_sticks = dict(pyui_sticks or {})  # abs code -> (stick, "x"/"y", sign of +)
        self.cfg_var = {}
        self.slot = {}
        self.absent = set()
        for slot, var, _pyui in SLOTS:
            spec = cfg_spec(var, env)
            if spec == ABSENT:
                self.absent.add(slot)
            control = spec_control(spec)
            if control is not None:
                self.cfg_var.setdefault(control, var)
                self.slot.setdefault(control, slot)
        if manifest is not None:  # what the device lacks, and the codes a placeholder cfg doesn't give
            self.absent = {slot for slot, _var, _pyui in SLOTS if manifest.has(slot) is False}
            for slot, _var, _pyui in SLOTS:
                control = spec_control(manifest.code(slot))
                if control is not None and slot not in self.slot.values():
                    self.slot.setdefault(control, slot)
        for control, pyui in self.pyui.items():
            slot = PYUI_SLOT.get(pyui)
            if slot and control not in self.slot and slot not in self.slot.values():
                self.slot[control] = slot
        self.sticks = {}  # stick -> {"x": (axis, sign), "y": (axis, sign), "vars": (...)}
        for stick, var_x, var_y, _dx, _dy in STICKS:
            x = stick_axis(cfg_spec(var_x, env))
            y = stick_axis(cfg_spec(var_y, env))
            over = manifest.over_cfg(f"{stick}_STICK") if manifest is not None else None
            if over:  # the hardware's axes, measured, where the cfg names others
                x = stick_axis(parse_spec(over.get("x"))) or x
                y = stick_axis(parse_spec(over.get("y"))) or y
            for code, (pstick, axis, psign) in self.pyui_sticks.items():
                if pstick == stick and axis == "x" and x is None:
                    x = (code, psign)
                if pstick == stick and axis == "y" and y is None:
                    y = (code, psign)
            entry = manifest.control(f"{stick}_STICK") if manifest is not None else {}
            if x is None:
                x = stick_axis(parse_spec(entry.get("x")))
            if y is None:
                y = stick_axis(parse_spec(entry.get("y")))
            if x or y:
                self.sticks[stick] = {"x": x, "y": y, "vars": (var_x, var_y)}

    def controls_of(self, slot):
        return [c for c, s in self.slot.items() if s == slot]

    def label(self, slot):
        """PyUI's name for the control in this slot, else the slot's spruce name."""
        for control in self.controls_of(slot):
            if control in self.pyui:
                return LABELS.get(self.pyui[control], self.pyui[control])
        return LABELS.get(dict((s, p) for s, _v, p in SLOTS).get(slot), slot)

    def describe(self, control):
        """'304 BTN_SOUTH = PyUI B, cfg B_B' for logs and the screen."""
        etype, code, csign = control
        text = f"{code} {key_name(code)}" if etype == EV_KEY else f"{code} {control_name(control)}"
        bits = []
        if control in self.pyui:
            bits.append(f"PyUI {self.pyui[control]}")
        if control in self.cfg_var:
            bits.append(f"cfg {self.cfg_var[control]}")
        return text + (" = " + ", ".join(bits) if bits else " (not in PyUI's table or the cfg)")

    def stick_role(self, code):
        """(stick, "x"/"y", sign of right/down) for an abs code, or None."""
        for stick, info in self.sticks.items():
            for axis in ("x", "y"):
                if info[axis] and info[axis][0] == code:
                    return stick, axis, info[axis][1]
        return None


def pyui_tables(controller_interface=None, device=None):
    """PyUI's tables, {control: ControllerInput name} and {abs code: stick role}, read from the
    provider's static dicts (never calling stateful providers); dArkMoss's L3/R3 from its fallback.
    """
    controls = {}
    sticks = {}
    provider = getattr(controller_interface, "mapping_provider", None)
    tables = [getattr(provider, "key_mappings", None)]
    try:
        tables.append(device._button_mappings())
    except Exception:  # only the dArkMoss devices have it
        pass
    for table in tables:
        if not isinstance(table, dict):
            continue
        for event, results in table.items():
            etype = getattr(event, "event_type", None)
            code = getattr(event, "code", None)
            value = signed(getattr(event, "value", 0) or 0)
            for result in results or []:
                state = getattr(getattr(result, "key_state", None), "name", "")
                pyui = getattr(getattr(result, "controller_input", None), "name", None)
                if state != "PRESS" or not pyui:
                    continue
                if etype == EV_KEY and value == 1:
                    controls.setdefault((EV_KEY, code, 1), pyui)
                elif etype == EV_ABS and value:
                    controls.setdefault((EV_ABS, code, sign(value)), pyui)
    for code, pyui in (getattr(provider, "THUMB_FALLBACK", None) or {}).items():
        controls.setdefault((EV_KEY, code, 1), getattr(pyui, "name", str(pyui)))
    axes = getattr(provider, "stick_axes", None) or getattr(provider, "STICK_AXES", None) or {}
    for code, axis in axes.items():
        low = getattr(axis, "left", None)
        high = getattr(axis, "right", None)
        if low is None:
            low = getattr(axis, "up", None)
            high = getattr(axis, "down", None)
        role = PYUI_STICK.get(getattr(high, "name", ""))
        if role:
            sticks[code] = role
    return controls, sticks
