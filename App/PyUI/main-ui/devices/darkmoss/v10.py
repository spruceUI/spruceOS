from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.darkmoss.darkmoss_device import DarkmossDevice
from devices.darkmoss.darkmoss_key_mapping_provider import DarkmossKeyMappingProvider


class V10KeyMappingProvider(DarkmossKeyMappingProvider):
    """The V10 has no menu button: SELECT+START is MENU.

    Pressing START while SELECT is held releases SELECT and presses MENU, so
    the UI never sees SELECT and START held together; releasing START releases
    MENU. SELECT's own release after the chord is swallowed, having already
    been sent.

    L3/R3 can also be configured as the menu button, using the same pattern as
    the RGB30: whichever thumb click matches the current menuButton setting
    becomes MENU, while the other remains L3/R3.
    """

    SELECT_KEY = 704
    START_KEY = 709
    L3_KEY = 705     # BTN_TRIGGER_HAPPY2
    R3_KEY = 708     # BTN_TRIGGER_HAPPY5

    THUMB_FALLBACK = {
        L3_KEY: ControllerInput.L3,
        R3_KEY: ControllerInput.R3,
    }

    def _menu_thumb_code(self):
        # Same logic as the RGB30: the user-selected thumb-click becomes MENU;
        # any other case leaves the other click as L3/R3.
        from devices.device import Device
        from utils.cfw_system_config import CfwSystemConfig

        option = CfwSystemConfig.get_menu_option("Button Settings", "menuButton") or {}
        if not Device.supports_device(option.get("devices")):
            return None
        if "R3" == option.get("selected"):
            return self.R3_KEY
        return self.L3_KEY

    def get_mapped_events(self, key_event):
        # Give L3/R3 the same menu-or-fallback behavior as other dArkMoss devices.
        if key_event.event_type == self.EV_KEY and key_event.code in self.THUMB_FALLBACK:
            return self._map_thumb_click(key_event)

        if key_event.event_type == self.EV_KEY:
            if key_event.code == self.SELECT_KEY:
                if key_event.value == 1:
                    self.select_down = True
                    self.select_released_by_chord = False
                elif key_event.value == 0:
                    self.select_down = False
                    if self.select_released_by_chord:
                        self.select_released_by_chord = False
                        return None
            elif key_event.code == self.START_KEY:
                if key_event.value == 1 and self.select_down:
                    self.menu_down = True
                    self.select_released_by_chord = True
                    return [InputResult(ControllerInput.SELECT, KeyState.RELEASE),
                            InputResult(ControllerInput.MENU, KeyState.PRESS)]
                if self.menu_down:
                    if key_event.value == 0:
                        self.menu_down = False
                        return [InputResult(ControllerInput.MENU, KeyState.RELEASE)]
                    return None  # autorepeat while the chord is held

        return super().get_mapped_events(key_event)


class V10(DarkmossDevice):
    """Powkiddy V10 on dArkMoss: RK3326, 320x480 portrait panel, OGA 1.1 pad."""

    JOYPAD_NODE = "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick"
    SYSTEM_JSON_NAME = "v10-system.json"
    # The 4.4 kernel lists the panel colour properties but rejects every set.
    PANEL_CALIBRATION = False
    SELECT_KEY = 704  # BTN_TRIGGER_HAPPY1, the "-" button
    START_KEY = 709   # BTN_TRIGGER_HAPPY6, the "+" button
    L2_KEY = 706
    R2_KEY = 707
    # The rk3326 base has no softvol Master and a 0-255 backlight: use the py-ui-config scripts.
    VOLUME_BACKLIGHT_CMDS = True

    def _button_mappings(self):
        key_mappings = super()._button_mappings()
        for code, control in ((self.L2_KEY, ControllerInput.L2), (self.R2_KEY, ControllerInput.R2)):
            key_mappings[KeyEvent(1, code, 1)] = [InputResult(control, KeyState.PRESS)]
            key_mappings[KeyEvent(1, code, 0)] = [InputResult(control, KeyState.RELEASE)]
        return key_mappings

    def _mapping_provider(self, key_mappings):
        return V10KeyMappingProvider(key_mappings)

    def screen_width(self):
        return 480

    def screen_height(self):
        return 320

    # The panel boots with fbcon=rotate:3, like the Miniloong, and dArkMoss's
    # base SDL for this unit is the RGA ROT_270 build, so PyUI turns its own
    # frames 270 degrees to match.
    def screen_rotation(self):
        return 270
