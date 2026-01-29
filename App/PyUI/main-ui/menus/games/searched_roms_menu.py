
import os
from devices.device import Device
from menus.games.roms_menu_common import RomsMenuCommon
from menus.games.utils.rom_select_options_builder import get_rom_select_options_builder
from utils.consts import GAME_SELECT
from views.grid_or_list_entry import GridOrListEntry


class SearchedRomsMenu(RomsMenuCommon):
    def __init__(self, search_str):
        super().__init__()
        self.search_str = search_str

    def include_rom(self,rom_file_name, rom_file_path):
        return self.search_str in rom_file_name.upper() or os.path.isdir(rom_file_path)
        
    def _get_rom_list(self) -> list[GridOrListEntry]:
        roms = []
        game_utils = Device.get_device().get_game_system_utils()

        def _collect_roms_recursively(game_system, directory=None):

            """Recursively collect roms for a given game_system and directory."""
            rom_list = get_rom_select_options_builder().build_rom_list(
                game_system,
                self.include_rom,
                subfolder=directory, 
                prefer_savestate_screenshot=self.prefer_savestate_screenshot()
            )
            all_roms = []

            # Iterate through entries to find directories
            for entry in rom_list:
                rom_path = entry.get_value().rom_file_path
                rom_name = os.path.basename(rom_path)
                if os.path.isdir(rom_path):
                    # Recurse into subdirectory
                    sub_roms = _collect_roms_recursively(game_system, rom_path)
                    all_roms.extend(sub_roms)
                    if(self.search_str in rom_name.upper()):
                        all_roms.append(entry)
                else:
                    all_roms.append(entry)

            return all_roms

        # Iterate all game systems
        for game_system in game_utils.get_active_systems():
            roms_for_system = _collect_roms_recursively(game_system)
            roms.extend(roms_for_system)

        return roms
    def run_rom_selection(self) :
        return self._run_rom_selection("Game Search")

    def prefer_savestate_screenshot(self):
        return Device.get_device().get_system_config().use_savestate_screenshots(GAME_SELECT)
