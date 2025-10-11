
import os
import subprocess
from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.games.roms_menu_common import RomsMenuCommon
from menus.games.utils.favorites_manager import FavoritesManager
from menus.games.utils.rom_info import RomInfo
from views.grid_or_list_entry import GridOrListEntry


class FavoritesMenu(RomsMenuCommon):
    def __init__(self):
        super().__init__()

    def _get_rom_list(self) -> list[GridOrListEntry]:
        rom_list = []
        favorites : list[RomInfo] = FavoritesManager.get_favorites()
        for rom_info in favorites:
            img_path = self._get_image_path(rom_info)

            display_name = rom_info.display_name
            if(display_name is None):
                display_name =  self._remove_extension(os.path.basename(rom_info.rom_file_path))

            rom_list.append(
                GridOrListEntry(
                    primary_text=display_name  +" (" + self._extract_game_system(rom_info.rom_file_path)+")",
                    image_path=img_path,
                    image_path_selected=img_path,
                    description="Favorite", 
                    icon=None,
                    value=rom_info)
            )
        return rom_list

    def run_rom_selection(self) :
        return self._run_rom_selection("Favorites")


    def sort_favorites_alphabetically(self, input_value):
        if(ControllerInput.A == input_value):
            FavoritesManager.sort_favorites_alphabetically()

    def get_additional_menu_options(self):
        popup_options = []
        popup_options.append(GridOrListEntry(
            primary_text="Sort Favorites",
            image_path=None,
            image_path_selected=None,
            description=f"Sort Favorites",
            icon=None,
            value=lambda input_value: self.sort_favorites_alphabetically(input_value)
        ))
        return popup_options
