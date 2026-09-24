import subprocess

from controller.controller_inputs import ControllerInput
from display.display import Display
from menus.games.utils.cheevos_cache_manager import CheevosCacheManager
from menus.language.language import Language
from menus.settings import settings_menu
from themes.theme import Theme
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry


class CheevosCacheMenu(settings_menu.SettingsMenu):
    """The games whose achievements are cached for offline play. Removing one
    frees a slot against the proxy's 100 game cap."""

    def remove(self, input_value, entry):
        if ControllerInput.A != input_value:
            return

        Display.display_message(Language.label("removingCheevos", "Removing..."))

        # No id means it was cached before the id was recorded, or by something
        # else. Drop our own record so the marker goes, and say so.
        if entry.game_id is None:
            CheevosCacheManager.remove_cached(entry.rom_file_path)
            Display.display_message(
                Language.label("cheevosForgotten", "Removed from the list only"),
                duration_ms=2500)
            return

        message = "Removed"
        remove_cmd = PyUiConfig.get_cheevos_remove_cmd()
        try:
            result = subprocess.run([remove_cmd, str(entry.game_id)],
                                    capture_output=True, text=True, timeout=60)
            if result.returncode != 0:
                lines = (result.stdout or result.stderr).strip().splitlines()
                message = lines[-1] if lines else "Remove failed"
        except Exception as e:
            PyUiLogger.get_logger().error(f"remove-cached-game failed: {e}")
            message = "Remove failed"

        CheevosCacheManager.remove_cached(entry.rom_file_path)
        Display.display_message(message, duration_ms=2500)

    def build_options_list(self):
        option_list = []

        for entry in sorted(CheevosCacheManager.get_cached(),
                            key=lambda e: (e.display_name or e.rom_file_path).lower()):
            option_list.append(
                GridOrListEntry(
                    primary_text=entry.display_name or entry.rom_file_path,
                    value_text=None,
                    image_path=None,
                    image_path_selected=None,
                    description=entry.game_system_name,
                    icon=Theme.cheevos_icon(),
                    value=lambda input_value, entry=entry: self.remove(input_value, entry)
                )
            )

        if not option_list:
            option_list.append(
                GridOrListEntry(
                    primary_text=Language.label("noCachedCheevos", "No cached games"),
                    value_text=None,
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value=lambda input_value: None
                )
            )

        return option_list
