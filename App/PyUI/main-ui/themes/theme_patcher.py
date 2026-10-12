from math import gcd

from themes.default_theme_patcher import DefaultThemePatcher
from utils.logger import PyUiLogger


class ThemePatcher():
    THEME_PATCHERS = {
        (4, 3): DefaultThemePatcher,
        (16, 9): DefaultThemePatcher,
    }

    @classmethod
    def patch_theme(cls, path, target_width, target_height):
        original_width = target_width
        original_height = target_height

        common_divisor = gcd(target_width, target_height)
        aspect_ratio = (
            target_width // common_divisor,
            target_height // common_divisor,
        )

        patcher = ThemePatcher.THEME_PATCHERS.get(aspect_ratio, DefaultThemePatcher)

        PyUiLogger.get_logger().info(f"Using {patcher.__name__} patcher")

        patcher.patch_theme(path, original_width, original_height)