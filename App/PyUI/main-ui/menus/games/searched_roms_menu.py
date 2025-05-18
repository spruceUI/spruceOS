
import os
import subprocess
from devices.device import Device
from games.utils.game_system_utils import GameSystemUtils
from menus.games.roms_menu_common import RomsMenuCommon
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.rom_select_options_builder import RomSelectOptionsBuilder
from views.grid_or_list_entry import GridOrListEntry


class SearchedRomsMenu(RomsMenuCommon):
    def __init__(self, search_str):
        super().__init__()
        self.rom_select_options_builder = RomSelectOptionsBuilder()
        self.search_str = search_str

    def include_rom(self,rom_file_path):
        rom_file_name = os.path.splitext(os.path.basename(rom_file_path))[0]
        return self.search_str in rom_file_name.upper()
    
    def _get_rom_list(self) -> list[GridOrListEntry]:
        roms = []
        game_utils = GameSystemUtils()
        for game_system in game_utils.get_active_systems():
            roms += self.rom_select_options_builder.build_rom_list(game_system, self.include_rom)
        
        return roms

    def run_rom_selection(self) :
        self._run_rom_selection("Game Search")
