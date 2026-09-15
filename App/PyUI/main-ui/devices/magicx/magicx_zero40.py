from devices.magicx.magicx_a133p_device import MagicXA133PDevice


class MagicXZero40(MagicXA133PDevice):
    """MagicX Zero 40: 4.0" 480x800 portrait-native touchscreen, dual sticks.

    The panel is portrait in the shell and DedicatedOS drives it 480x800 with
    no rotation, so the UI is portrait-logical and touch maps 1:1 (rotation 0).
    These three values must match DISPLAY_* in spruce/scripts/platform/Zero40.cfg;
    for a landscape UI held sideways set 800/480 and 90 (or 270) in both places
    and the touch layer inverts the rotation for you.
    """

    def __init__(self, device_name, main_ui_mode):
        super().__init__(device_name, main_ui_mode, "/mnt/SDCARD/Saves/magicx-zero40-system.json")

    def screen_width(self):
        return 480

    def screen_height(self):
        return 800

    def screen_rotation(self):
        return 0

    def supports_touch(self):
        return True
