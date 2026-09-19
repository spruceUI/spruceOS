import os
from devices.magicx.magicx_a133p_device import MagicXA133PDevice


class MagicXXU20(MagicXA133PDevice):
    """MagicX / XU RETRO XU20 V32: 3.2" 1024x768 landscape panel, touch, no sticks.

    The RTP32HD016A panel is landscape-native and its Hynitron touch controller
    is configured for the same 1024x768 with no axis swap or inversion, so the
    UI is landscape rotated 180 (the panel scans upside down relative to the case;
    the vendor's Android rotates it the same way) and touch is inverted on both axes.

    Like the Zero boards this device runs our own Tina kernel, booted behind its
    stock boot0 and U-Boot; the panel and the Hynitron touch driver are both ours
    (confirmed on hardware 2026-09-17). Nothing in this class depends on that; the
    difference lives in the SD1 image and in the platform cfg.

    These three values must match DISPLAY_* in spruce/scripts/platform/XU20.cfg.
    """

    BACKLIGHT_REVERSED = True  # see MagicXA133PDevice._set_lumination_to_config

    def __init__(self, device_name, main_ui_mode):
        super().__init__(device_name, main_ui_mode, "/mnt/SDCARD/Saves/magicx-xu20-system.json")

    # Geometry and rotation come from the platform cfg on the card (DISPLAY_WIDTH /
    # DISPLAY_HEIGHT / DISPLAY_ROTATION); the literals below are the defaults.
    def _env_int(self, name, default):
        try:
            return int(os.environ.get(name, "").strip() or default)
        except ValueError:
            return default

    def screen_width(self):
        return self._env_int("DISPLAY_WIDTH", 1024)

    def screen_height(self):
        return self._env_int("DISPLAY_HEIGHT", 768)

    def screen_rotation(self):
        return self._env_int("DISPLAY_ROTATION", 180)

    def supports_touch(self):
        return True
