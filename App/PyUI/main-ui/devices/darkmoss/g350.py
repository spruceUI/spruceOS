from devices.darkmoss.darkmoss_device import DarkmossDevice


class G350(DarkmossDevice):
    """BatleXP G350 on dArkMoss: RK3326, 640x480, the RG351MP-family pad."""

    JOYPAD_NODE = "/dev/input/by-path/platform-odroidgo3-joypad-event-joystick"
    SYSTEM_JSON_NAME = "g350-system.json"
    # The 4.4 kernel lists the panel colour properties but rejects every set.
    PANEL_CALIBRATION = False
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
