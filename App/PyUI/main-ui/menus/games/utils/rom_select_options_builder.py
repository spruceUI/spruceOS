

import os
from pathlib import Path
from typing import Callable
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from games.utils.box_art_resizer import BoxArtResizer
from games.utils.rom_utils import RomUtils
from menus.games.utils.favorites_manager import FavoritesManager
from menus.games.utils.miyoo_game_list import MiyooGameList
from menus.games.utils.rom_info import RomInfo
from themes.theme import Theme
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry


class RomSelectOptionsBuilder:
    _user_doesnt_want_to_resize = False

    def __init__(self):
        self.roms_path = Device.get_roms_dir()
        self.rom_utils : RomUtils= RomUtils(self.roms_path)
        
    
    def get_rom_name_without_extensions(self, game_system, file_path) -> str:
        # Remove all known extensions from the filename
        base_name = os.path.splitext(os.path.basename(file_path))[0]
        ext_list = game_system.game_system_config.get_extlist()
        while True:
            next_base, next_ext = os.path.splitext(base_name)
            if next_ext.lower() in ext_list:
                base_name = next_base
            else:
                break
        return base_name

    def get_image_path(self, rom_info: RomInfo, game_entry = None) -> str:
        if(game_entry is not None):
            if(os.path.exists(game_entry.image)):
                return game_entry.image
        # Get the base filename without extension
        base_name = self.get_rom_name_without_extensions(rom_info.game_system, rom_info.rom_file_path)

        # Normalize and split the path into components
        parts = os.path.normpath(rom_info.rom_file_path).split(os.sep)

        try:
            roms_index = next(i for i, part in enumerate(parts) if part.lower() == "roms")
        except (ValueError, IndexError):
            PyUiLogger.get_logger().info(f"Roms not found in {rom_info.rom_file_path}")
            return None  # "Roms" not in path or nothing after "Roms"

        # Build path to the image using the extracted directory
        root_dir = os.sep.join(parts[:roms_index+2])  # base path before Roms

        qoi_path = os.path.join(root_dir, "Imgs", base_name + ".qoi")
        if os.path.exists(qoi_path) and Device.supports_qoi():
            return qoi_path

        image_path = os.path.join(root_dir, "Imgs", base_name + ".png")

        if os.path.exists(image_path):
            if(Device.supports_qoi()):
                if(not RomSelectOptionsBuilder._user_doesnt_want_to_resize):
                    if(Device.get_system_config().never_prompt_boxart_resize()):
                        RomSelectOptionsBuilder._user_doesnt_want_to_resize = True
                    else:
                        Display.display_message_multiline([f"Would you like to optimize boxart?",
                                                           "Originals will be converted, be sure to backup!",
                                                           "A = Yes, B = No, X/Y = Never Prompt",
                                                           "",
                                                           "You can manually do this in:",
                                                           "Settings -> Extra Settings -> Optimize BoxArt"], 0)
                        input = Controller.wait_for_input([ControllerInput.A,ControllerInput.B,ControllerInput.X,ControllerInput.Y])
                        
                        if(input == ControllerInput.B):
                            RomSelectOptionsBuilder._user_doesnt_want_to_resize = True
                        elif(input == ControllerInput.X or input == ControllerInput.Y):
                            Device.get_system_config().set_never_prompt_boxart_resize(True)
                            RomSelectOptionsBuilder._user_doesnt_want_to_resize = True

                if(not RomSelectOptionsBuilder._user_doesnt_want_to_resize):
                    RomSelectOptionsBuilder._user_doesnt_want_to_resize = True
                    BoxArtResizer.process_rom_folders()
                if os.path.exists(qoi_path) and Device.supports_qoi():
                    return qoi_path
                else:
                    return image_path
            else:
                return image_path

        
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
        
        #ES format
        imgs_folder_with_image_suffix = os.path.join(root_dir, "Imgs", base_name + "-image.png")
        if os.path.exists(imgs_folder_with_image_suffix):
            return imgs_folder_with_image_suffix

        #ES format2
        imgs_folder_equal_to_roms_path_with_thumb_suffix = os.path.join(root_dir, "Imgs", base_name + "-thumb.png")
        if os.path.exists(imgs_folder_equal_to_roms_path_with_thumb_suffix):
            return imgs_folder_equal_to_roms_path_with_thumb_suffix

        #ES format same folder
        imgs_folder_equal_to_roms_path_with_image_suffix = os.path.join(os.sep.join(imgs_older_equal_to_roms_parts[:-1]), base_name + "-image.png")
        if os.path.exists(imgs_folder_equal_to_roms_path_with_image_suffix):
            return imgs_folder_equal_to_roms_path_with_image_suffix
        
        #ES format2 same folder
        imgs_folder_equal_to_roms_path_with_thumb_suffix = os.path.join(os.sep.join(imgs_older_equal_to_roms_parts[:-1]), base_name + "-thumb.png")
        if os.path.exists(imgs_folder_equal_to_roms_path_with_thumb_suffix):
            return imgs_folder_equal_to_roms_path_with_thumb_suffix

        #File itself is a png
        if rom_info.rom_file_path.lower().endswith(".png"):
            return rom_info.rom_file_path
        
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
        

    def build_rom_list(self, game_system,filter: Callable[[str, str], bool] = lambda a,b: True, subfolder = None) -> list[GridOrListEntry]:
        file_rom_list = []
        folder_rom_list = []
        valid_files, valid_folders = self.rom_utils.get_roms(game_system, subfolder)
        

        miyoo_game_list = MiyooGameList(self.rom_utils.get_miyoo_games_file(game_system.folder_name))
        
        for rom_file_path in valid_files:
            rom_file_name = os.path.basename(rom_file_path)
            game_entry = miyoo_game_list.get_by_file_path(rom_file_path)
            if(filter(rom_file_name, rom_file_path)):
                if(game_entry is not None):
                    display_name = game_entry.name
                else:
                    display_name = self.get_rom_name_without_extensions(game_system,rom_file_path)

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
            rom_info = RomInfo(game_system,rom_file_path)
            rom_file_name = os.path.basename(rom_file_path)
            if(filter(rom_file_name, rom_file_path)):

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
