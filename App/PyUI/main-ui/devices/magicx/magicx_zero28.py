import os
from devices.magicx.magicx_a133p_device import MagicXA133PDevice


class MagicXZero28(MagicXA133PDevice):
    """MagicX Mini Zero 28: 2.8" 640x480 panel mounted portrait, no touch.

    screen_rotation matches DISPLAY_ROTATION in spruce/scripts/platform/Zero28.cfg
    (MinUI's zero28 port rotates by the same +90).
    """

    def __init__(self, device_name, main_ui_mode):
        super().__init__(device_name, main_ui_mode, "/mnt/SDCARD/Saves/magicx-zero28-system.json")

    # Geometry and rotation come from the platform cfg on the card (DISPLAY_WIDTH /
    # DISPLAY_HEIGHT / DISPLAY_ROTATION); the literals below are the defaults.
    def _env_int(self, name, default):
        try:
            return int(os.environ.get(name, "").strip() or default)
        except ValueError:
            return default

    def screen_width(self):
        return self._env_int("DISPLAY_WIDTH", 640)

    def screen_height(self):
        return self._env_int("DISPLAY_HEIGHT", 480)

    def screen_rotation(self):
        return self._env_int("DISPLAY_ROTATION", 0)
