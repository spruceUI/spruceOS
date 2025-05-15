
import os
from pathlib import Path
import subprocess
from controller.controller import Controller
from devices.device import Device
from display.display import Display
from menus.games.roms_menu_common import RomsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry


class RecentsMenu(RomsMenuCommon):
    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme):
        super().__init__(display,controller,device,theme)

    def _get_rom_list(self) -> list[GridOrListEntry]:
        rom_list = []
        favorites = self.device.parse_recents()
        for favorite in favorites:
            rom_file_name = os.path.basename(favorite.rom_path)
            img_path = self._get_image_path(favorite.rom_path)
            rom_list.append(
                GridOrListEntry(
                    primary_text=self._remove_extension(rom_file_name)  +" (" + self._extract_game_system(favorite.rom_path)+")",
                    image_path=img_path,
                    image_path_selected=img_path,
                    description="Favorite", 
                    icon=None,
                    value=favorite.rom_path)
            )
        return rom_list

    def run_rom_selection(self) :
        self._run_rom_selection("Recents")