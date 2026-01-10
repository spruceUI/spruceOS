
from typing import List
from devices.device import Device
from display.resize_type import ResizeType
from menus.games.recents_menu import RecentsMenu
from menus.games.utils.custom_gameswitcher_list_manager import CustomGameSwitcherListManager
from menus.games.utils.recents_manager import RecentsManager
from menus.games.utils.rom_info import RomInfo
from themes.theme import Theme
from utils.consts import GAME_SWITCHER
from utils.py_ui_config import PyUiConfig


class RecentsMenuGS(RecentsMenu):
    def __init__(self):
        super().__init__()

    
    def run_rom_selection(self) :
        return self._run_rom_selection("Game Switcher")
    
    def get_amount_of_recents_to_allow(self):
        return Device.get_device().get_system_config().game_switcher_game_count()

    def default_to_last_game_selection(self):
        return False
   
    def prefer_savestate_screenshot(self):
        return Device.get_device().get_system_config().use_savestate_screenshots(GAME_SWITCHER)

    def get_rom_list(self) -> List[RomInfo]:
        if(PyUiConfig.get_gameswitcher_path() is not None and Device.get_device().get_system_config().use_custom_gameswitcher_path()):
            return CustomGameSwitcherListManager.get_recents()
        else:
            return RecentsManager.get_recents()
        
    def get_view_type(self):
        return Theme.get_view_type_for_game_switcher()
    
    def full_screen_grid_resize_type(self):
        return Theme.get_resize_type_for_game_switcher()

    def get_set_top_bar_text_to_game_selection(self):
        return Theme.get_set_top_bar_text_to_game_selection_for_game_switcher()

    def get_image_resize_height_multiplier(self):
        if(ResizeType.ZOOM == Theme.get_resize_type_for_game_switcher() and Theme.true_full_screen_game_switcher()):
            return 1.0
        else:
            return None  
