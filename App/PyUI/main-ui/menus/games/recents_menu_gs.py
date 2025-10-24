
import os
from devices.device import Device
from display.display import Display
from menus.games.recents_menu import RecentsMenu
from menus.games.roms_menu_common import RomsMenuCommon
from menus.games.utils.recents_manager import RecentsManager
from menus.games.utils.rom_info import RomInfo
from views.grid_or_list_entry import GridOrListEntry
from views.view_type import ViewType


class RecentsMenuGS(RecentsMenu):
    def __init__(self):
        super().__init__()

    def get_view_type(self):
        return ViewType.FULLSCREEN_GRID

    def run_rom_selection(self) :
        return self._run_rom_selection("Game Switcher")

    def get_amount_of_recents_to_allow(self):
        return Device.get_system_config().game_switcher_game_count()
