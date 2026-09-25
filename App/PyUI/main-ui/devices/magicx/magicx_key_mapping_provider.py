import os

from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent

DEADZONE = 16000


def _env_flag(name, default):
    v = os.environ.get(name, "").strip()
    return default if v == "" else v not in ("0", "false", "False", "no")


def _env_codes(name, default):
    """Comma-separated key codes from the platform cfg, else the default set.

    The pad is the same driver on every board in this family, but the codes are
    not: each board's device tree names them, and some buttons carry a second
    code (linux,code2) that the driver emits alongside the first. On the XU20
    V32 that makes B send KEY_BACK 158, the code the Zero boards use for MENU,
    so the cfg has to be able to move MENU (to BTN_0 256 there) and to add 158
    to the ignored set without a rebuild.
    """
    out = set()
    for part in os.environ.get(name, "").replace(";", ",").split(","):
        part = part.strip()
        if not part:
            continue
        try:
            out.add(int(part))
        except ValueError:
            continue
    return out or set(default)


class MagicXKeyMappingProvider:
    """Key map for the MagicX simplepad ("magicx-input", a UART MCU pad).

    Derived from MinUI's zero28 platform.h joystick indices (A=0 B=1 X=2 Y=3
    L1=4 R1=5 L2=6 R2=7 SELECT=8 START=9 L3=10 R3=11, UP=13 LEFT=14 RIGHT=15
    DOWN=16, MINUS=17 PLUS=18 MENU=19) under SDL's evdev enumeration order
    (BTN_JOYSTICK.. first, then 0..BTN_JOYSTICK): the face buttons are
    304/305/307/308 = A/B/X/Y, the triggers are buttons 312/313, the d-pad is
    KEY_UP/LEFT/RIGHT/DOWN 103/105/106/108, MENU is KEY_BACK 158 and the
    volume keys 115/114 ride the same device. Unlike the TrimUI map, A and B
    (and X and Y) are not swapped and there is no ABS hat. Sticks: ABS 0/1
    left, 2/5 right (measured on the Zero 28).
    """

    def __init__(self):
        self.key_mappings = {}
        buttons = {
            304: ControllerInput.A, 305: ControllerInput.B,
            307: ControllerInput.X, 308: ControllerInput.Y,
            310: ControllerInput.L1, 311: ControllerInput.R1,
            312: ControllerInput.L2, 313: ControllerInput.R2,
            314: ControllerInput.SELECT, 315: ControllerInput.START,
            103: ControllerInput.DPAD_UP, 108: ControllerInput.DPAD_DOWN,
            105: ControllerInput.DPAD_LEFT, 106: ControllerInput.DPAD_RIGHT,
            172: ControllerInput.HOME,
        }
        # MENU is KEY_BACK 158 on the Zero boards (measured on the Zero 28), with the
        # usual MENU codes as fallbacks. The XU20 overrides this to 256 from its cfg.
        for _code in _env_codes("MAGICX_MENU_CODES", (158, 139, 316)):
            buttons[_code] = ControllerInput.MENU
        # Stick direction and axis layout differ per board: DedicatedOS (Zero 40) has
        # horizontal = -ABS_Y, MinUI (Zero 28) plain ABS_X/ABS_Y. Set from the cfg.
        self.swap_xy = _env_flag("MAGICX_STICK_SWAP_XY", False)
        self.invert_x = _env_flag("MAGICX_STICK_INVERT_X", False)
        self.invert_y = _env_flag("MAGICX_STICK_INVERT_Y", False)
        self._reported = set()
        for code, ci in buttons.items():
            self.key_mappings[KeyEvent(1, code, 1)] = [InputResult(ci, KeyState.PRESS)]
            self.key_mappings[KeyEvent(1, code, 0)] = [InputResult(ci, KeyState.RELEASE)]
        # A also emits KEY_SELECT 353 alongside BTN_SOUTH, so 353 is ignored; 272/273
        # are the driver's virtual-mouse buttons. The XU20 adds 158, B's second code.
        self.ignored_codes = _env_codes("MAGICX_IGNORED_CODES", (353, 272, 273))
        # An ignored code must never also be mapped: the cfg moves MENU off a
        # code precisely because another button emits it too.
        for _code in self.ignored_codes:
            self.key_mappings.pop(KeyEvent(1, _code, 1), None)
            self.key_mappings.pop(KeyEvent(1, _code, 0), None)

    LEFT_STICK = ((ControllerInput.LEFT_STICK_LEFT, ControllerInput.LEFT_STICK_RIGHT),
                  (ControllerInput.LEFT_STICK_UP, ControllerInput.LEFT_STICK_DOWN))
    RIGHT_STICK = ((ControllerInput.RIGHT_STICK_LEFT, ControllerInput.RIGHT_STICK_RIGHT),
                   (ControllerInput.RIGHT_STICK_UP, ControllerInput.RIGHT_STICK_DOWN))
    # Left stick on ABS_X/ABS_Y, right on ABS_Z/ABS_RZ (measured on the Zero 28).
    STICK_AXES = {0: (LEFT_STICK, 0), 1: (LEFT_STICK, 1), 2: (RIGHT_STICK, 0), 5: (RIGHT_STICK, 1)}

    def get_mapped_events(self, key_event):
        mappings = self.key_mappings.get(key_event)
        if mappings is None and key_event.event_type == 1 and key_event.code in self.ignored_codes:
            return None
        if mappings is None and key_event.event_type == 1 and key_event.value == 1 and key_event.code not in self._reported:
            # Bring-up aid: name every key code this pad sends that the map
            # does not know, once per code (the Zero 40's MENU, 2026-09-16).
            self._reported.add(key_event.code)
            try:
                from utils.logger import PyUiLogger
                PyUiLogger.get_logger().info(f"MagicX pad: unmapped key code {key_event.code} pressed")
            except Exception:
                pass
        if mappings is None and key_event.event_type == 3 and key_event.code in self.STICK_AXES:
            stick, axis = self.STICK_AXES[key_event.code]
            if self.swap_xy:
                axis = 1 - axis
            neg, pos = stick[axis]
            value = key_event.value
            if (axis == 0 and self.invert_x) or (axis == 1 and self.invert_y):
                value = -value
            if value < -DEADZONE:
                return [InputResult(neg, KeyState.PRESS)]
            if value > DEADZONE:
                return [InputResult(pos, KeyState.PRESS)]
            return [InputResult(neg, KeyState.RELEASE), InputResult(pos, KeyState.RELEASE)]
        return mappings
