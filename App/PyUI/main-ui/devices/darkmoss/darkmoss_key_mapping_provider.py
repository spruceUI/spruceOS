from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher_controller import HorizontalStickAxis, VerticalStickAxis
from controller.key_watcher_controller_dataclasses import InputResult


class DarkmossKeyMappingProvider:
    """Buttons from a plain dict, plus both analog sticks as d-pad input.

    The pad reports its axes on a -1800..1800 range, not the +-32767 SDL scale
    the TrimUI provider assumes, so the deadzone is sized for this device -
    measured with evtest on hardware, which also gives fuzz 16 / flat 16 and a
    rest value of exactly 0 on all four axes.
    """

    ABS_X = 0
    ABS_Y = 1
    ABS_RX = 3
    ABS_RY = 4
    EV_KEY = 1
    EV_ABS = 3
    DEADZONE = 900

    BTN_THUMBL = 317
    BTN_THUMBR = 318

    # What a stick click does when it is NOT the menu button. Nothing in the UI
    # consumes L3/R3 today, so this is effectively no action - but reporting the
    # real button beats swallowing the event, and it costs nothing if a view
    # ever grows a use for them. Emulators are unaffected either way: they read
    # the pad themselves, so both clicks stay L3/R3 in game.
    THUMB_FALLBACK = {
        BTN_THUMBL: ControllerInput.L3,
        BTN_THUMBR: ControllerInput.R3,
    }

    def __init__(self, key_mappings):
        self.key_mappings = key_mappings
        self.stick_axes = {
            self.ABS_X: HorizontalStickAxis(ControllerInput.LEFT_STICK_LEFT, ControllerInput.LEFT_STICK_RIGHT),
            self.ABS_Y: VerticalStickAxis(ControllerInput.LEFT_STICK_UP, ControllerInput.LEFT_STICK_DOWN),
            self.ABS_RX: HorizontalStickAxis(ControllerInput.RIGHT_STICK_LEFT, ControllerInput.RIGHT_STICK_RIGHT),
            self.ABS_RY: VerticalStickAxis(ControllerInput.RIGHT_STICK_UP, ControllerInput.RIGHT_STICK_DOWN),
        }
        # Which input each click reported when it went down, so its release
        # always matches - the setting can change between the two.
        self.thumb_pressed_as = {}

    def _menu_thumb_code(self):
        # Read per click rather than caching: the controller is built once at
        # init, so a cached value would need a PyUI restart to take effect.
        # CfwSystemConfig serves this from its in-memory copy, and a stick click
        # is not a hot path. Anything but R3, including a missing option on an
        # older config, leaves the L3 default. A device the option does not
        # list has a real menu key, so neither click is the menu.
        from devices.device import Device
        from utils.cfw_system_config import CfwSystemConfig
        option = CfwSystemConfig.get_menu_option("Button Settings", "menuButton") or {}
        if not Device.supports_device(option.get("devices")):
            return None
        if "R3" == option.get("selected"):
            return self.BTN_THUMBR
        return self.BTN_THUMBL

    def _map_thumb_click(self, key_event):
        if key_event.value == 1:
            control = (ControllerInput.MENU
                       if key_event.code == self._menu_thumb_code()
                       else self.THUMB_FALLBACK[key_event.code])
            self.thumb_pressed_as[key_event.code] = control
            return [InputResult(control, KeyState.PRESS)]
        if key_event.value == 0:
            control = self.thumb_pressed_as.pop(key_event.code, None)
            if control is None:
                return None
            return [InputResult(control, KeyState.RELEASE)]
        return None  # autorepeat

    def get_mapped_events(self, key_event):
        if key_event.event_type == self.EV_KEY and key_event.code in self.THUMB_FALLBACK:
            return self._map_thumb_click(key_event)

        if key_event.event_type != self.EV_ABS:
            return self.key_mappings.get(key_event)

        axis = self.stick_axes.get(key_event.code)
        if axis is None:
            return None
        return axis.get_mapped_events(key_event.value, self.DEADZONE)
