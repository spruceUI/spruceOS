from devices.rgb30.rgb30 import Rgb30


class G350(Rgb30):
    """BatleXP G350 on dArkMoss: RK3326, 640x480, the RG351MP-family pad."""

    JOYPAD_NODE = "/dev/input/by-path/platform-odroidgo3-joypad-event-joystick"
    SYSTEM_JSON = "/mnt/SDCARD/App/PyUI/config/g350-system.json"
    SYSTEM_JSON_DEFAULT = "g350-system.json"
    SYSTEM_JSON_DIR = "g350"
    SELECT_KEY = 704  # BTN_TRIGGER_HAPPY1
    START_KEY = 705
    MENU_KEY = 708    # F5

    # Mirrors SYSTEM_BRIGHTNESS_0..10 in spruce/scripts/platform/G350.cfg.
    BACKLIGHT_TABLE = (5, 6, 10, 16, 32, 48, 64, 96, 128, 191, 255)

    def screen_width(self):
        return 640

    def screen_height(self):
        return 480
