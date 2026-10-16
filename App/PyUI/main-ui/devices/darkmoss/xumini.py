from devices.darkmoss.darkmoss_device import DarkmossDevice


class XuMiniM(DarkmossDevice):
    """MagicX XU Mini M on dArkMoss: RK3326, 480x640 portrait, xu10-joypad.

    A/B/X/Y/L1/R1/L2/R2/dpad and the default SELECT_KEY/START_KEY
    (314/315) already match this pad's codes; only a real MENU_KEY and the
    portrait-to-landscape software rotation are new here.
    """

    JOYPAD_NODE = "/dev/input/by-path/platform-xu10-joypad-event-joystick"
    SYSTEM_JSON_NAME = "xumini-system.json"
    # The 4.4 kernel lists the panel colour properties but rejects every set.
    PANEL_CALIBRATION = False
    MENU_KEY = 704  # BTN_TRIGGER_HAPPY1, a real button here
    BATTERYPLUS_PERCENT_FILE = "/tmp/battery.percent"
    # The rk3326 base has no softvol Master and a 0-100 backlight: use the py-ui-config scripts.
    VOLUME_BACKLIGHT_CMDS = True

    def screen_width(self):
        return 640

    def screen_height(self):
        return 480

    # Knulli boots this panel with fbcon=rotate:1 (90 degrees), and
    # build_sdl2.sh builds the base's SDL with the matching RGA ROT_90
    # variant - so PyUI's own software rotation has to agree: 90, not the
    # 270 the Miniloong (a rotate:3 panel) uses.
    def screen_rotation(self):
        return 90
