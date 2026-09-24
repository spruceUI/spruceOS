
import subprocess

from controller.controller_inputs import ControllerInput
from display.display import Display
from menus.games.utils.cheevos_cache_manager import CheevosCacheManager
from menus.language.language import Language
from menus.settings import settings_menu
from menus.settings.cheevos_cache_menu import CheevosCacheMenu
from utils.cfw_system_config import CfwSystemConfig
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry


class CfwSystemSettingsMenuForCategory(settings_menu.SettingsMenu):
    RETROACHIEVEMENTS = "RetroAchievements Settings"

    def __init__(self, category):
        self.category = category
        super().__init__()

    def launch_cheevos_cache(self, input_value):
        if ControllerInput.A == input_value:
            CheevosCacheMenu().show_menu()

    def show_cheevos_cache(self):
        return (self.category == self.RETROACHIEVEMENTS
                and PyUiConfig.get_cheevos_cache_path()
                and "True" == CfwSystemConfig.get_selected_value(
                    self.RETROACHIEVEMENTS, "enableOfflineProxy"))

    def update_cheevos_cache(self, input_value):
        if ControllerInput.A != input_value:
            return

        entries = CheevosCacheManager.get_cached()
        if not entries:
            Display.display_message(
                Language.label("noCachedCheevos", "No cached games"), duration_ms=2000)
            return

        cache_cmd = PyUiConfig.get_cache_cheevos_cmd()
        updated = 0
        failed = 0
        for index, entry in enumerate(entries, start=1):
            Display.display_message(
                Language.label("updatingCheevos", "Updating {current} of {total}...")
                    .replace("{current}", str(index)).replace("{total}", str(len(entries))))
            try:
                result = subprocess.run([cache_cmd, entry.rom_file_path],
                                        capture_output=True, text=True, timeout=300)
                if result.returncode == 0:
                    updated += 1
                    lines = (result.stdout or result.stderr).strip().splitlines()
                    _, game_id = CheevosCacheManager.parse_result(lines)
                    if game_id is not None and game_id != entry.game_id:
                        CheevosCacheManager.set_game_id(entry.rom_file_path, game_id)
                else:
                    failed += 1
            except Exception as e:
                PyUiLogger.get_logger().error(f"cheevos update failed: {e}")
                failed += 1

        summary = Language.label("updatedCheevos", "Updated {updated}").replace("{updated}", str(updated))
        if failed:
            summary = f"{summary}, {failed} failed"
        Display.display_message(summary, duration_ms=2500)

    def build_options_list(self):
        option_list = self.build_options_list_from_config_menu_options(self.category)

        if self.show_cheevos_cache():
            option_list.append(
                GridOrListEntry(
                    primary_text=Language.label("cachedCheevosGames", "Cached Games"),
                    value_text=None,
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value=self.launch_cheevos_cache
                )
            )

            option_list.append(
                GridOrListEntry(
                    primary_text=Language.label("updateCheevosCache", "Update Cached Games"),
                    value_text=None,
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value=self.update_cheevos_cache
                )
            )

        return option_list
