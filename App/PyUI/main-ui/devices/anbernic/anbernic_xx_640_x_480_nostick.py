from devices.anbernic.anbernic_xx_common import AnbernicXXCommon


class Anbernic640x480NoStick(AnbernicXXCommon):
    """RG35XX Plus and RG35XX SP: the 640x480 panel without sticks. Its own platform, like Brick Pro next to Brick, so every
    config ships static for its pad layout; the shell side exports
    XX_PAD_LAYOUT from the platform cfg."""

    def __init__(self, main_ui_mode):
        self.device_name = "ANBERNIC_RGXX640480NOSTICK"
        super().__init__(main_ui_mode)

    def screen_width(self):
        return 640

    def screen_height(self):
        return 480

    def screen_rotation(self):
        return 0
