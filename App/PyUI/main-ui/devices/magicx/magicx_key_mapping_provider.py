from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent

DEADZONE = 16000


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
    left, 2/3 right. To be confirmed against the key bitmap in the diag log.
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
            158: ControllerInput.MENU,
        }
        for code, ci in buttons.items():
            self.key_mappings[KeyEvent(1, code, 1)] = [InputResult(ci, KeyState.PRESS)]
            self.key_mappings[KeyEvent(1, code, 0)] = [InputResult(ci, KeyState.RELEASE)]
        # L3/R3 (317/318) are the driver's virtual-mouse keys; left unmapped.

    def get_mapped_events(self, key_event):
        mappings = self.key_mappings.get(key_event)
        if mappings is None and key_event.event_type == 3 and key_event.code in (0, 1):
            neg, pos = ((ControllerInput.LEFT_STICK_LEFT, ControllerInput.LEFT_STICK_RIGHT) if key_event.code == 0
                        else (ControllerInput.LEFT_STICK_UP, ControllerInput.LEFT_STICK_DOWN))
            if key_event.value < -DEADZONE:
                return [InputResult(neg, KeyState.PRESS)]
            if key_event.value > DEADZONE:
                return [InputResult(pos, KeyState.PRESS)]
            return [InputResult(neg, KeyState.RELEASE), InputResult(pos, KeyState.RELEASE)]
        return mappings
