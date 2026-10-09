
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from menus.games.utils import raproxy_cli
from menus.games.utils.cheevos_cache_manager import CheevosCacheManager
from menus.language.language import Language
from menus.settings import settings_menu
from menus.settings.cheevos_cache_menu import CheevosCacheMenu
from menus.settings.pending_awards_menu import PendingAwardsMenu
from views.grid_or_list_entry import GridOrListEntry


class CfwSystemSettingsMenuForCategory(settings_menu.SettingsMenu):
    RETROACHIEVEMENTS = "RetroAchievements Settings"

    def __init__(self, category):
        self.category = category
        super().__init__()

    def launch_cheevos_cache(self, input_value):
        if ControllerInput.A == input_value:
            Display.display_message(Language.label("loadingCheevos", "Loading..."))
            CheevosCacheManager.refresh()
            CheevosCacheMenu().show_menu()

    def show_cheevos_cache(self):
        return self.category == self.RETROACHIEVEMENTS and raproxy_cli.enabled()

    def launch_pending_awards(self, input_value):
        if ControllerInput.A == input_value:
            PendingAwardsMenu().show_menu()

    def library_path(self):
        return Device.get_device().get_roms_dir()

    def toggle_library(self, input_value):
        if input_value not in (ControllerInput.A, ControllerInput.DPAD_LEFT, ControllerInput.DPAD_RIGHT):
            return
        raproxy_cli.toggle_watch(self.library_path(), Language.label("keepLibraryOffline", "Keep library offline"))

    def cache_recently_played(self, input_value):
        if ControllerInput.A != input_value:
            return
        message = raproxy_cli.run_smart_cache(
            Language.label("cacheRecentCheevos", "Cache recently played games"))
        if message:
            Display.display_message(message, duration_ms=2500)

    def cheevos_entry(self, text, value, value_text=None, description=None):
        return GridOrListEntry(
            primary_text=text,
            value_text=value_text,
            image_path=None,
            image_path_selected=None,
            description=description,
            icon=None,
            value=value
        )

    def build_options_list(self):
        option_list = self.build_options_list_from_config_menu_options(self.category)

        if self.show_cheevos_cache():
            library_on = raproxy_cli.is_watched(self.library_path())
            option_list.append(self.cheevos_entry(
                Language.label("cachedCheevosGames", "Cached Games"), self.launch_cheevos_cache))
            option_list.append(self.cheevos_entry(
                Language.label("pendingCheevosAwards", "Pending Awards"), self.launch_pending_awards))
            option_list.append(self.cheevos_entry(
                Language.label("keepLibraryOffline", "Keep library offline"), self.toggle_library,
                value_text="<    " + Language.menu_option_value("True" if library_on else "False") + "    >",
                description=Language.label("keepLibraryOfflineDesc", "Cache every game, including ones added later")))
            option_list.append(self.cheevos_entry(
                Language.label("cacheRecentCheevos", "Cache recently played games"), self.cache_recently_played))

        return option_list
