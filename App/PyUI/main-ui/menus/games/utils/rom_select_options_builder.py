

import os
from pathlib import Path
from typing import Callable
from devices.device import Device
from games.utils.rom_utils import RomUtils
from menus.games.utils.favorites_manager import FavoritesManager
from menus.games.utils.miyoo_game_list import MiyooGameList
from menus.games.utils.rom_info import RomInfo
from themes.theme import Theme
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry


class RomSelectOptionsBuilder:
    def __init__(self):
        self.roms_path = Device.get_roms_dir()
        self.rom_utils : RomUtils= RomUtils(self.roms_path)
        
    
    def get_image_path(self, rom_info: RomInfo, game_entry = None) -> str:
        if(game_entry is not None):
            return game_entry.image
        # Get the base filename without extension
        base_name = os.path.splitext(os.path.basename(rom_info.rom_file_path))[0]
        
        # Normalize and split the path into components
        parts = os.path.normpath(rom_info.rom_file_path).split(os.sep)

        try:
            roms_index = next(i for i, part in enumerate(parts) if part.lower() == "roms")
        except (ValueError, IndexError):
            PyUiLogger.get_logger().info(f"Roms not found in {rom_info.rom_file_path}")
            return None  # "Roms" not in path or nothing after "Roms"

        # Build path to the image using the extracted directory
        root_dir = os.sep.join(parts[:roms_index+2])  # base path before Roms
        image_path = os.path.join(root_dir, "Imgs", base_name + ".png")

        if os.path.exists(image_path):
            return image_path
        else:
            # Attempt to construct alternate path by replacing "Roms" with "Imgs"
            imgs_older_equal_to_roms_parts = parts.copy()
            imgs_older_equal_to_roms_parts[roms_index] = "Imgs"
            imgs_folder_equal_to_roms_path = os.path.join(os.sep.join(imgs_older_equal_to_roms_parts[:-1]), base_name + ".png")

            if os.path.exists(imgs_folder_equal_to_roms_path):
                return imgs_folder_equal_to_roms_path
            else:
                #Check for png in same dir
                same_dir_png = os.path.join(root_dir, base_name + ".png")
                if os.path.exists(same_dir_png):
                    return same_dir_png
                
        # Else try the muOS location
        muos_image_path_sd2 = os.path.join("/mnt/sdcard/MUOS/info/catalogue/", rom_info.game_system.game_system_config.system_name, "box", base_name + ".png")
        if os.path.exists(muos_image_path_sd2):
            return muos_image_path_sd2

        muos_image_path_sd1 = os.path.join("/mnt/mmc/MUOS/info/catalogue/", rom_info.game_system.game_system_config.system_name, "box", base_name + ".png")
        if os.path.exists(muos_image_path_sd1):
            return muos_image_path_sd1

        return None

    def _build_favorites_dict(self):
        favorites = Device.parse_favorites()
        favorite_paths = []
        for favorite in favorites:
            favorite_paths.append(str(Path(favorite.rom_path).resolve()))

        return favorite_paths

    def _get_favorite_icon(self, rom_info: RomInfo) -> str:
        if FavoritesManager.is_favorite(rom_info):
            return Theme.favorite_icon()
        else:
            return None
        

    def build_rom_list(self, game_system,filter: Callable[[str], bool] = lambda a: True, subfolder = None) -> list[GridOrListEntry]:
        file_rom_list = []
        folder_rom_list = []
        valid_files, valid_folders = self.rom_utils.get_roms(game_system, subfolder)
        

        miyoo_game_list = MiyooGameList(self.rom_utils.get_miyoo_games_file(game_system.folder_name))
        
        for rom_file_path in valid_files:
            if(filter(rom_file_path)):
                rom_file_name = os.path.basename(rom_file_path)
                game_entry = miyoo_game_list.get_by_file_name(rom_file_name)
                if(game_entry is not None):
                    display_name = game_entry.name
                else:
                    display_name = os.path.splitext(rom_file_name)[0]

                rom_info = RomInfo(game_system,rom_file_path, display_name)

                file_rom_list.append(
                    GridOrListEntry(
                        primary_text=display_name,
                        description=game_system.folder_name, 
                        value=rom_info,
                        image_path_searcher= lambda rom_info=rom_info, game_entry=game_entry: self.get_image_path(rom_info, game_entry),
                        image_path_selected_searcher= lambda rom_info=rom_info, game_entry=game_entry: self.get_image_path(rom_info, game_entry),
                        icon_searcher=lambda rom_info=rom_info: self._get_favorite_icon(rom_info)
                    )
                )

        for rom_file_path in valid_folders:
            if(filter(rom_file_name)):
                rom_info = RomInfo(game_system,rom_file_path)
                rom_file_name = os.path.basename(rom_file_path)

                folder_rom_list.append(
                    GridOrListEntry(
                        primary_text=rom_file_name,
                        description=game_system.folder_name, 
                        value=rom_info,
                        image_path_searcher=lambda rom_info: self.get_image_path(rom_info),
                        image_path_selected_searcher=lambda rom_info: self.get_image_path(rom_info),
                        icon_searcher=lambda rom_info: self._get_favorite_icon(rom_info)
                    )
                )

        file_rom_list.sort(key=lambda entry: entry.get_primary_text())   
        folder_rom_list.sort(key=lambda entry: entry.get_primary_text())   

        return folder_rom_list + file_rom_list
