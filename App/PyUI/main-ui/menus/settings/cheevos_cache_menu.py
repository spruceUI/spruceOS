import subprocess

from controller.controller_inputs import ControllerInput
from display.display import Display
from menus.games.utils.cheevos_cache_manager import CheevosCacheManager
from menus.language.language import Language
from menus.settings import settings_menu
from menus.settings.list_of_options_selection_menu import ListOfOptionsSelectionMenu
from themes.theme import Theme
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry


class CheevosCacheMenu(settings_menu.SettingsMenu):

    def show_entry_menu(self, input_value, entry):
        if ControllerInput.A != input_value:
            return

        choice = ListOfOptionsSelectionMenu().get_selected_option_index(
            [Language.label("removeFromCheevosCache", "Remove from cache")],
            entry.title)

        if choice == 0:
            self.remove(entry)

    def remove(self, entry):
        Display.display_message(Language.label("removingCheevos", "Removing..."))

        message = "Remove failed"
        remove_cmd = PyUiConfig.get_cheevos_remove_cmd()
        try:
            result = subprocess.run([remove_cmd, str(entry.game_id)],
                                    capture_output=True, text=True, timeout=60)
            if result.returncode == 0:
                CheevosCacheManager.refresh()
                message = "Removed"
            else:
                lines = (result.stdout or result.stderr).strip().splitlines()
                if lines:
                    message = lines[-1]
        except Exception as e:
            PyUiLogger.get_logger().error(f"remove-cached-game failed: {e}")

        Display.display_message(message, duration_ms=2500)

    def build_options_list(self):
        option_list = []

        for entry in sorted(CheevosCacheManager.get_cached(), key=lambda e: (e.title or "").lower()):
            option_list.append(
                GridOrListEntry(
                    primary_text=entry.title,
                    value_text=None,
                    image_path=None,
                    image_path_selected=None,
                    description=entry.rom_path or Language.label(
                        "cheevosOnlinePlay", "Cached from online play"),
                    icon=Theme.cheevos_icon(),
                    value=lambda input_value, entry=entry: self.show_entry_menu(input_value, entry)
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
