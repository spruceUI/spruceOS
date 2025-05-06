
import os
from pathlib import Path
import subprocess
from controller.controller import Controller
from devices.device import Device
from display.display import Display
from games.utils.game_entry import GameEntry
from games.utils.rom_utils import RomUtils
from menus.games.roms_menu_common import RomsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry


class GameSelectMenu(RomsMenuCommon):
    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme):
        super().__init__(display,controller,device,theme)
        self.roms_path = "/mnt/sdcard/Roms/"
        self.rom_utils : RomUtils= RomUtils(self.roms_path)

    def _is_favorite(self, favorites: list[GameEntry], rom_file_path):
        return any(Path(rom_file_path).resolve() == Path(fav.rom_path).resolve() for fav in favorites)

    def _get_rom_list(self) -> list[GridOrListEntry]:
        rom_list = []
        favorites = self.device.parse_favorites()
        for rom_file_path in self.rom_utils.get_roms(self.game_system):
            rom_file_name = os.path.basename(rom_file_path)
            img_path = self._get_image_path(rom_file_path)
            icon=self.theme.favorite_icon if self._is_favorite(favorites, rom_file_path) else None
            rom_list.append(
                GridOrListEntry(
                    primary_text=self._remove_extension(rom_file_name),
                    image_path=img_path,
                    image_path_selected=img_path,
                    description=self.game_system, 
                    icon=icon,
                    value=rom_file_path)
            )
        return rom_list

    def run_rom_selection(self,game_system) :
        self.game_system = game_system
        self._run_rom_selection(game_system)