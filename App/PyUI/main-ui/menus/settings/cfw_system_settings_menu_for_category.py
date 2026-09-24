
from controller.controller_inputs import ControllerInput
from menus.language.language import Language
from menus.settings import settings_menu
from menus.settings.cheevos_cache_menu import CheevosCacheMenu
from utils.cfw_system_config import CfwSystemConfig
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

        return option_list
