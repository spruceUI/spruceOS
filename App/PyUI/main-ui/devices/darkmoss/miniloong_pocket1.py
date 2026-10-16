import threading

from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.charge.charge_status import ChargeStatus
from devices.darkmoss.darkmoss_device import DarkmossDevice
from devices.darkmoss.miniloong_key_mapping_provider import MiniloongKeyMappingProvider
from utils import throttle
from utils.logger import PyUiLogger


class MiniloongPocket1(DarkmossDevice):
    """Miniloong Pocket 1 on dArkMoss: RK3566, 960x720 portrait panel used in
    landscape and rendered at 1.5x, a real menu button, one stick."""

    JOYPAD_NODE = "/dev/input/by-path/platform-singleadc-joypad-event-joystick"
    SYSTEM_JSON_NAME = "miniloong-system.json"
    MENU_KEY = 316  # BTN_MODE

    # Mirrors SYSTEM_BRIGHTNESS_0..10 in spruce/scripts/platform/Miniloong.cfg.
    # The panel is black at raw 60 and below.
    BACKLIGHT_TABLE = (70, 77, 83, 90, 96, 103, 109, 116, 122, 129, 135)
    BACKLIGHT_FLOOR = 70

    def __init__(self, device_name, main_ui_mode=True):
        super().__init__(device_name)
        if main_ui_mode:
            threading.Thread(target=self._set_lumination_to_config, daemon=True).start()

    def _button_mappings(self):
        key_mappings = super()._button_mappings()
        for code, control in ((317, ControllerInput.L3), (318, ControllerInput.R3)):
            key_mappings[KeyEvent(1, code, 1)] = [InputResult(control, KeyState.PRESS)]
            key_mappings[KeyEvent(1, code, 0)] = [InputResult(control, KeyState.RELEASE)]
        return key_mappings

    def _mapping_provider(self, key_mappings):
        return MiniloongKeyMappingProvider(key_mappings)

    def screen_width(self):
        return 960

    def screen_height(self):
        return 720

    def screen_rotation(self):
        return 270

    def output_screen_width(self):
        if self.should_scale_screen():
            return 1920
        return int(self.screen_width() * 1.5)

    def output_screen_height(self):
        if self.should_scale_screen():
            return 1080
        return int(self.screen_height() * 1.5)

    def get_scale_factor(self):
        return 2 if self.is_hdmi_connected() else 1.5

    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        try:
            with open("/sys/class/drm/card0-HDMI-A-1/status") as f:
                return f.read().strip().lower() == "connected"
        except OSError:
            return False

    def _set_lumination_to_config(self):
        level = max(0, min(10, int(self.system_config.backlight)))
        raw = max(self.BACKLIGHT_FLOOR, self.BACKLIGHT_TABLE[level])
        try:
            with open("/sys/class/backlight/backlight/brightness", "w") as f:
                f.write(str(raw))
            with open("/sys/class/backlight/backlight/bl_power", "w") as f:
                f.write("0")
        except OSError as e:
            PyUiLogger.get_logger().error(f"Miniloong: backlight write failed: {e}")

    @throttle.limit_refresh(5)
    def get_charge_status(self):
        for node in ("/sys/class/power_supply/usb/online", "/sys/class/power_supply/ac/online"):
            try:
                with open(node) as f:
                    if int(f.read().strip()):
                        return ChargeStatus.CHARGING
            except (OSError, ValueError):
                continue
        return ChargeStatus.DISCONNECTED
