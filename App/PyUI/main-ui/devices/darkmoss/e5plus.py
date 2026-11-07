from devices.darkmoss.darkmoss_device import DarkmossDevice


class E5Plus(DarkmossDevice):
    """GameMT E5 Plus on dArkMoss: RK3566, 720x1280 portrait panel used as
    1280x720 landscape, a real menu button (F), two sticks."""

    JOYPAD_NODE = "/dev/input/by-path/platform-singleadc-joypad-event-joystick"
    SYSTEM_JSON_NAME = "e5plus-system.json"
    MENU_KEY = 316  # BTN_MODE, the F button
    # Mirrors SYSTEM_BACKLIGHT_LEVEL_0..10 in spruce/scripts/platform/darkmoss/E5Plus.cfg.
    BACKLIGHT_TABLE = (4, 6, 10, 16, 32, 48, 64, 96, 128, 192, 255)

    def screen_width(self):
        return 1280

    def screen_height(self):
        return 720

    # The panel scans out 720x1280; dArkMoss turns its console with
    # fbcon=rotate:1 (90 clockwise), the Miniloong's opposite.
    def screen_rotation(self):
        return 90
