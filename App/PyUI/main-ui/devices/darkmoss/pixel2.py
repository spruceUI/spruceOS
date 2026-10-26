from devices.darkmoss.darkmoss_device import DarkmossDevice


class Pixel2DarkMoss(DarkmossDevice):
    """GKD Pixel 2 on dArkMoss: RK3326S, 480x640 portrait, singleadc-joypad, no sticks.

    The default codes (A/B/X/Y, L1-R2, SELECT/START, d-pad 544-547) match this
    pad; MENU is its F1 key. GKD_PIXEL2 is the Twig-Next base, not this class.
    """

    JOYPAD_NODE = "/dev/input/by-path/platform-gamekiddy-joypad-event-joystick"
    SYSTEM_JSON_NAME = "pixel2-darkmoss-system.json"
    # UNVERIFIED on the 5.10 kernel: off as on the 4.4 rk3326 units until a set is seen to work.
    PANEL_CALIBRATION = False
    MENU_KEY = 704  # BTN_TRIGGER_HAPPY1, the F1 key
    # The rk3326 base has no softvol Master: use the py-ui-config scripts.
    VOLUME_BACKLIGHT_CMDS = True

    def screen_width(self):
        return 640

    def screen_height(self):
        return 480

    # The panel boots with fbcon=rotate:3 and the base SDL is the RGA ROT_270
    # build (as the V10's), so PyUI turns its own frames 270 degrees to match.
    def screen_rotation(self):
        return 270
