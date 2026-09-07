from devices.anbernic.anbernic_xx_common import AnbernicXXCommon


class Anbernic640x480OneStick(AnbernicXXCommon):
    """RG40XX V: the 640x480 panel with one stick (L3 present, no R3). Its own platform, like Brick Pro next to Brick, so every
    config ships static for its pad layout; the shell side exports
    XX_PAD_LAYOUT from the platform cfg."""

    def __init__(self, main_ui_mode):
        self.device_name = "ANBERNIC_RGXX640480ONESTICK"
        super().__init__(main_ui_mode)

    def screen_width(self):
        return 640

    def screen_height(self):
        return 480

    def screen_rotation(self):
        return 0
