from devices.darkmoss.rgb30 import Rgb30


class G350(Rgb30):
    """BatleXP G350 on dArkMoss: RK3326, 640x480, the RG351MP-family pad."""

    JOYPAD_NODE = "/dev/input/by-path/platform-odroidgo3-joypad-event-joystick"
    SYSTEM_JSON = "/mnt/SDCARD/App/PyUI/config/g350-system.json"
    SYSTEM_JSON_DEFAULT = "json/g350-system.json"
    SYSTEM_JSON_DIR = "g350"
    SELECT_KEY = 704  # BTN_TRIGGER_HAPPY1
    START_KEY = 705
    MENU_KEY = 708    # F5
    BATTERYPLUS_PERCENT_FILE = "/tmp/battery.percent"
    # The rk3326 base has no softvol Master and a 0-100 backlight: use the py-ui-config scripts.
    VOLUME_BACKLIGHT_CMDS = True

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
