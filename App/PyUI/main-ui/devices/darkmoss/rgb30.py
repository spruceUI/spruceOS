from devices.darkmoss.darkmoss_device import DarkmossDevice


class Rgb30(DarkmossDevice):
    """Powkiddy RGB30 on dArkMoss: RK3566, 720x720, no menu button."""

    JOYPAD_NODE = "/dev/input/by-path/platform-singleadc-joypad-event-joystick"
    SYSTEM_JSON_NAME = "rgb30-system.json"
    # Mirrors SYSTEM_BACKLIGHT_LEVEL_0..10 in spruce/scripts/platform/RGB30.cfg.
    BACKLIGHT_TABLE = (4, 6, 10, 16, 32, 48, 64, 96, 128, 192, 255)

    def screen_width(self):
        return 720

    def screen_height(self):
        return 720
