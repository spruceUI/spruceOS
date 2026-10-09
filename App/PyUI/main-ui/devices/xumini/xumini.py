from devices.rgb30.rgb30 import Rgb30


class XuMiniM(Rgb30):
    """MagicX XU Mini M on dArkMoss: RK3326, 480x640 portrait, xu10-joypad.

    A/B/X/Y/L1/R1/L2/R2/dpad and Rgb30's own SELECT_KEY/START_KEY defaults
    (314/315) already match this pad's codes; only a real MENU_KEY and the
    portrait-to-landscape software rotation are new here.
    """

    JOYPAD_NODE = "/dev/input/by-path/platform-xu10-joypad-event-joystick"
    SYSTEM_JSON = "/mnt/SDCARD/App/PyUI/config/xumini-system.json"
    SYSTEM_JSON_DEFAULT = "xumini-system.json"
    SYSTEM_JSON_DIR = "xumini"
    MENU_KEY = 704  # BTN_TRIGGER_HAPPY1, a real button here

    # Mirrors SYSTEM_BRIGHTNESS_0..10 in spruce/scripts/platform/XUMiniM.cfg;
    # this backlight's max_brightness is 100, not the A10Mini's 255.
    BACKLIGHT_TABLE = (3, 4, 6, 10, 20, 30, 40, 60, 80, 90, 100)
    # No softvol on the rk3326 base: the rk817 codec's own volume control.
    VOLUME_CONTROL = "Playback"

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
