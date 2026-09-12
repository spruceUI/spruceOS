from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.miyoo_trim_mapping_provider import MiyooTrimKeyMappingProvider


class MiniloongKeyMappingProvider(MiyooTrimKeyMappingProvider):
    """The Loong Gamepad (evdev "Loong Gamepad", event4) on its physical codes.

    The Flip/TrimUI table this extends was written for Miyoo's driver, which
    reports the X button as BTN_WEST (308) and Y as BTN_NORTH (307). The Loong
    pad follows the Linux gamepad convention instead: X is BTN_NORTH (307) -
    captured on the MLP1 on 2026-09-04 while the user pressed X - so under the
    inherited table X arrived as Y and the power prompt's "X = Reboot" never
    fired (SPR-MED-195). A and B agree with the inherited table (A = 305, the
    menu's power-off worked).

    From the pad's own capability bits (/proc/bus/input/devices, KEY bitmask):
    it declares BTN_TL2/BTN_TR2 (312/313) as KEYS and no ABS 2/5, so the
    triggers are buttons here, not the analog axes the Flip table listens on;
    and a single thumb click, BTN_THUMBL (317), which Miniloong.cfg already
    treats as L3. Sticks stay on ABS 0/1 with the inherited +-32767 deadzone
    (Jawaka: 16-bit axes on this pad).
    """

    def __init__(self):
        super().__init__()

        def bind(code, control):
            self.key_mappings[KeyEvent(1, code, 1)] = [InputResult(control, KeyState.PRESS)]
            self.key_mappings[KeyEvent(1, code, 0)] = [InputResult(control, KeyState.RELEASE)]

        bind(307, ControllerInput.X)   # BTN_NORTH - measured
        bind(308, ControllerInput.Y)   # BTN_WEST
        bind(312, ControllerInput.L2)  # BTN_TL2, a key on this pad
        bind(313, ControllerInput.R2)  # BTN_TR2, a key on this pad
        bind(317, ControllerInput.L3)  # BTN_THUMBL, the only stick click declared
        # The volume keys are on this node too (DT VOLUMEDOWN_key/VOLUMEUP_key,
        # captured 2026-09-04). Controller.get_input hands them to
        # Device.special_input, the way the separate KeyWatcher does elsewhere.
        bind(114, ControllerInput.VOLUME_DOWN)
        bind(115, ControllerInput.VOLUME_UP)

        # The Flip table's analog-trigger entries (ABS 2/5 at 255) have no source
        # on this pad; drop them so a stale entry can never shadow the keys above.
        for event in (KeyEvent(3, 2, 0), KeyEvent(3, 2, 255), KeyEvent(3, 5, 0), KeyEvent(3, 5, 255)):
            self.key_mappings.pop(event, None)
