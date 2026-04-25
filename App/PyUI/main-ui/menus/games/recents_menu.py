
import sys
from devices.device import Device
from menus.games.roms_menu_common import RomsMenuCommon
from menus.games.utils.recents_manager import RecentsManager
from menus.games.utils.rom_file_name_utils import RomFileNameUtils
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.rom_select_options_builder import get_rom_select_options_builder
from utils.consts import RECENTS
from views.grid_or_list_entry import GridOrListEntry
from typing import List

from views.rom_grid_or_list_entry import RomGridOrListEntry

class RecentsMenu(RomsMenuCommon):
    def __init__(self):
        super().__init__()

    def get_description(self, rom_info: RomInfo) -> str:
        return rom_info.game_system.display_name

    def get_amount_of_recents_to_allow(self):
        return sys.maxsize
    
    def get_rom_list(self) -> List[RomInfo]:
        return RecentsManager.get_recents()
    
    def _get_rom_list(self) -> list[GridOrListEntry]:
        rom_list = []
        recents : list[RomInfo] = self.get_rom_list()[:self.get_amount_of_recents_to_allow()]
        get_image_path_fn = get_rom_select_options_builder().get_image_path

        for rom_info in recents:
            display_name = rom_info.display_name
            if(display_name is None):
                display_name =  RomFileNameUtils.get_rom_name_without_extensions(rom_info.game_system, rom_info.rom_file_path)

            rom_list.append(
                RomGridOrListEntry(
                        display_name=display_name  +" (" + self._extract_game_system(rom_info.rom_file_path)+")",
                        folder_name="Recents",
                        game_system=rom_info.game_system,
                        rom_file_path=rom_info.rom_file_path,
                        game_entry=None,
                        prefer_savestate_screenshot=self.prefer_savestate_screenshot(),
                        get_image_path_fn=get_image_path_fn,
                        get_favorite_icon=None
                )

            )
        return rom_list

    def run_rom_selection(self) :
        return self._run_rom_selection("Recents")


    def prefer_savestate_screenshot(self):
        return Device.get_device().get_system_config().use_savestate_screenshots(RECENTS)
