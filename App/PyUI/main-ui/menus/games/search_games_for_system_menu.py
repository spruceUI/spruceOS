
import os
import subprocess
from devices.device import Device
from games.utils.game_system import GameSystem
from menus.games.roms_menu_common import RomsMenuCommon
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.rom_select_options_builder import RomSelectOptionsBuilder
from views.grid_or_list_entry import GridOrListEntry


class SearchGamesForSystemMenu(RomsMenuCommon):
    def __init__(self, game_system : GameSystem, search_str):
        super().__init__()
        self.rom_select_options_builder = RomSelectOptionsBuilder()
        self.game_system = game_system
        self.search_str = search_str

    def include_rom(self,rom_file_path):
        rom_file_name = os.path.splitext(os.path.basename(rom_file_path))[0]
        return self.search_str in rom_file_name.upper()
    
    def _get_rom_list(self) -> list[GridOrListEntry]:
        return self.rom_select_options_builder.build_rom_list(self.game_system, self.include_rom)

    def run_rom_selection(self) :
        return self._run_rom_selection(f"{self.game_system.display_name} Search")
