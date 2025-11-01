
from devices.device import Device
from display.resize_type import ResizeType
from menus.games.recents_menu import RecentsMenu
from themes.theme import Theme
from utils.consts import GAME_SWITCHER
from views.view_type import ViewType


class RecentsMenuGS(RecentsMenu):
    def __init__(self):
        super().__init__()

    def get_view_type(self):
        return Theme.get_view_type_for_game_switcher()
    
    def full_screen_grid_resize_type(self):
        return Theme.get_resize_type_for_game_switcher()

    def get_set_top_bar_text_to_game_selection(self):
        return Theme.get_set_top_bar_text_to_game_selection_for_game_switcher()
    
    def run_rom_selection(self) :
        return self._run_rom_selection("Game Switcher")

    def get_amount_of_recents_to_allow(self):
        return Device.get_system_config().game_switcher_game_count()

    def default_to_last_game_selection(self):
        return False
   
    def prefer_savestate_screenshot(self):
        return Device.get_system_config().use_savestate_screenshots(GAME_SWITCHER)
