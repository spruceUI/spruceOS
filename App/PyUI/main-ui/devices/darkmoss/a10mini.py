from devices.darkmoss.darkmoss_device import DarkmossDevice
from devices.darkmoss.darkmoss_common import RK3326_PANEL_CALIBRATION


class A10Mini(DarkmossDevice):
    """A10 Mini on dArkMoss: RK3326, 640x480, the RG351MP pad."""

    JOYPAD_NODE = "/dev/input/by-path/platform-odroidgo3-joypad-event-joystick"
    SYSTEM_JSON_NAME = "a10mini-system.json"
    PANEL_CALIBRATION = RK3326_PANEL_CALIBRATION
    SELECT_KEY = 704  # BTN_TRIGGER_HAPPY1
    START_KEY = 705
    MENU_KEY = 708    # F5

    # Mirrors SYSTEM_BACKLIGHT_LEVEL_0..10 in spruce/scripts/platform/A10Mini.cfg.
    BACKLIGHT_TABLE = (3, 4, 6, 10, 20, 30, 40, 60, 80, 120, 160)

    def screen_width(self):
        return 640

    def screen_height(self):
        return 480
