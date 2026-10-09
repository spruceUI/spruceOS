from devices.rgb30.rgb30 import Rgb30


class A10Mini(Rgb30):
    """A10 Mini on dArkMoss: RK3326, 640x480, the RG351MP pad."""

    JOYPAD_NODE = "/dev/input/by-path/platform-odroidgo3-joypad-event-joystick"
    SYSTEM_JSON = "/mnt/SDCARD/App/PyUI/config/a10mini-system.json"
    SYSTEM_JSON_DEFAULT = "a10mini-system.json"
    SYSTEM_JSON_DIR = "a10mini"
    SELECT_KEY = 704  # BTN_TRIGGER_HAPPY1
    START_KEY = 705
    MENU_KEY = 708    # F5

    # Mirrors SYSTEM_BRIGHTNESS_0..10 in spruce/scripts/platform/A10Mini.cfg.
    BACKLIGHT_TABLE = (3, 4, 6, 10, 20, 30, 40, 60, 80, 120, 160)

    def screen_width(self):
        return 640

    def screen_height(self):
        return 480

    # The 4.4 kernel lists the panel colour properties but rejects every set.
    def supports_brightness_calibration(self):
        return False

    def supports_contrast_calibration(self):
        return False

    def supports_saturation_calibration(self):
        return False

    def supports_hue_calibration(self):
        return False
