from devices.darkmoss.darkmoss_device import DarkmossDevice


class Rg353m(DarkmossDevice):
    """Anbernic RG353M on dArkMoss: RK3566, 640x480."""

    JOYPAD_NODE = "/dev/input/by-path/platform-singleadc-joypad-event-joystick"
    SYSTEM_JSON_NAME = "rg353m-system.json"
    # Mirrors SYSTEM_BACKLIGHT_LEVEL_0..10 in spruce/scripts/platform/RG353M.cfg.
    BACKLIGHT_TABLE = (4, 6, 10, 16, 32, 48, 64, 96, 128, 192, 255)
    MENU_KEY = 316  # BTN_MODE, the FN key the RGB30 lacks

    def screen_width(self):
        return 640

    def screen_height(self):
        return 480
