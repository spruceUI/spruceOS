

import os
from pathlib import Path
from typing import Callable
from devices.device import Device
from games.utils.rom_utils import RomUtils
from menus.games.utils.favorites_manager import FavoritesManager
from menus.games.utils.rom_info import RomInfo
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry


class RomSelectOptionsBuilder:
    def __init__(self):
        self.roms_path = "/mnt/SDCARD/Roms/"
        self.rom_utils : RomUtils= RomUtils(self.roms_path)
        
    
    def _remove_extension(self,file_name):
        return os.path.splitext(file_name)[0]

    def get_image_path(self, rom_path):
        # Get the base filename without extension
        base_name = os.path.splitext(os.path.basename(rom_path))[0]
        
        # Normalize and split the path into components
        parts = os.path.normpath(rom_path).split(os.sep)

        try:
            roms_index = parts.index("Roms")
            first_after_roms = parts[roms_index + 1]
        except (ValueError, IndexError):
            return None  # "Roms" not in path or nothing after "Roms"

        # Build path to the image using the extracted directory
        root_dir = os.sep.join(parts[:roms_index+2])  # base path before Roms
        image_path = os.path.join(root_dir, "Imgs", base_name + ".png")

        if os.path.exists(image_path):
            return image_path
        else:
            return None


    def _build_favorites_dict(self):
        favorites = Device.parse_favorites()
        favorite_paths = []
        for favorite in favorites:
            favorite_paths.append(str(Path(favorite.rom_path).resolve()))

        return favorite_paths

    def build_rom_list(self, game_system, filter: Callable[[str], bool] = lambda a: True, subfolder = None) -> list[GridOrListEntry]:
        rom_list = []
        for rom_file_path in self.rom_utils.get_roms(game_system.folder_name, subfolder):
            if(filter(rom_file_path)):
                rom_file_name = os.path.basename(rom_file_path)
                img_path = self.get_image_path(rom_file_path)
                rom_info = RomInfo(game_system,rom_file_path)
                icon=Theme.favorite_icon() if FavoritesManager.is_favorite(rom_info) else None

                rom_list.append(
                    GridOrListEntry(
                        primary_text=self._remove_extension(rom_file_name),
                        image_path=img_path,
                        image_path_selected=img_path,
                        description=game_system.folder_name, 
                        icon=icon,
                        value=RomInfo(game_system,rom_file_path))
                )

        return rom_list
