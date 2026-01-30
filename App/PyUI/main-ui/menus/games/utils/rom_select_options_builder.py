

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
from menus.games.utils.rom_file_name_utils import RomFileNameUtils
from menus.games.utils.rom_info import RomInfo
from themes.theme import Theme
from utils.cached_exists import CachedExists
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry


class RomSelectOptionsBuilder:
    _user_doesnt_want_to_resize = False

    def __init__(self):
        self.roms_path = Device.get_device().get_roms_dir()
        self.rom_utils : RomUtils= RomUtils(self.roms_path)
        
    
    def get_default_image_path(self, game_system, rom_file_path):
        parts = os.path.normpath(rom_file_path).split(os.sep)
        try:
            roms_index = next(i for i, part in enumerate(parts) if part.lower() == "roms")
        except (ValueError, IndexError):
            PyUiLogger.get_logger().info(f"Roms not found in {rom_file_path}")
            return None  # "Roms" not in path or nothing after "Roms"

        # Get the base filename without extension
        base_name = RomFileNameUtils.get_rom_name_without_extensions(game_system, rom_file_path)

        # Build path to the image using the extracted directory
        root_dir = os.sep.join(parts[:roms_index+2])  # base path before Roms

        return os.path.join(root_dir, "Imgs", base_name + ".png")

    def first_existing(self, base_path_without_ext):
        IMAGE_EXTS = (".qoi", ".png")
        for ext in IMAGE_EXTS:
            path = base_path_without_ext + ext
            if CachedExists.exists(path):
                return path
        return None

    def get_image_path(self, rom_info: RomInfo, game_entry = None, prefer_savestate_screenshot = False) -> str:

        if(prefer_savestate_screenshot):
            # Use RA savestate image
            save_state_image_path = Device.get_device().get_save_state_image(rom_info)
            if save_state_image_path is not None and CachedExists.exists(save_state_image_path):
                return save_state_image_path


        if(game_entry is not None):
            if(CachedExists.exists(game_entry.image)):
                return game_entry.image

        # [Added] If the original ext files are not available, change it to .qoi and check again.
            if Device.get_device().supports_qoi() and game_entry.image:
                qoi_path = os.path.splitext(game_entry.image)[0] + ".qoi"
                if CachedExists.exists(qoi_path):
                    return qoi_path

        # Get the base filename without extension
        base_name = RomFileNameUtils.get_rom_name_without_extensions(rom_info.game_system, rom_info.rom_file_path)

        # Normalize and split the path into components
        parts = os.path.normpath(rom_info.rom_file_path).split(os.sep)

        try:
            roms_index = next(i for i, part in enumerate(parts) if part.lower() == "roms")
        except (ValueError, IndexError):
            PyUiLogger.get_logger().info(f"Roms not found in {rom_info.rom_file_path}")
            return None

        # Expected layout: ... /Roms/<system>/...
        if roms_index + 2 >= len(parts):
            return None  # No system or filename

        system_index = roms_index + 1  # MD
        system_dir = parts[system_index]

        # Path pieces after the system folder (subfolders + filename)
        relative_parts = parts[system_index + 1 : -1]

        # Build mirrored Imgs path
        mirrored_path_base = os.path.join(
            os.sep.join(parts[:system_index + 1]),  # Folder/Roms/MD
            "Imgs",
            *relative_parts,
            base_name
        )

        mirrored_qoi_path = mirrored_path_base + ".qoi"

        if CachedExists.exists(mirrored_qoi_path) and Device.get_device().supports_qoi():
            return mirrored_qoi_path

        # ---- Fallback to old behavior (top-level image) ----
        flat_root = os.path.join(os.sep.join(parts[:system_index + 1]), "Imgs", base_name)
        flat_qoi_path = flat_root+ ".qoi"

        if CachedExists.exists(flat_qoi_path) and Device.get_device().supports_qoi():
            return flat_qoi_path
        
        NON_QOI_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".bmp") 

        # Each entry is: (non_qoi_base, qoi_base)
        PATH_VARIANTS = (
            (mirrored_path_base, mirrored_qoi_path),
            (flat_root,          flat_qoi_path),
        )

        image_non_qoi_path = None
        image_qoi_path = None

        for base_path, qoi_path in PATH_VARIANTS:
            for ext in NON_QOI_EXTS:
                candidate = base_path + ext
                if CachedExists.exists(candidate):
                    image_non_qoi_path = candidate
                    image_qoi_path = qoi_path
                    break
            if image_non_qoi_path:
                break

        if image_non_qoi_path is not None:
            if(Device.get_device().supports_qoi()):
                if(not RomSelectOptionsBuilder._user_doesnt_want_to_resize):
                    if(Device.get_device().get_system_config().never_prompt_boxart_resize()):
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
                            Device.get_device().get_system_config().set_never_prompt_boxart_resize(True)
                            RomSelectOptionsBuilder._user_doesnt_want_to_resize = True

                if(not RomSelectOptionsBuilder._user_doesnt_want_to_resize):
                    RomSelectOptionsBuilder._user_doesnt_want_to_resize = True
                    BoxArtResizer.process_rom_folders()
                if CachedExists.exists(image_qoi_path) and Device.get_device().supports_qoi():
                    return image_qoi_path
                else:
                    return image_non_qoi_path
            else:
                return image_non_qoi_path

        
        # Attempt to construct alternate path by replacing "Roms" with "Imgs"
        imgs_older_equal_to_roms_parts = parts.copy()
        imgs_older_equal_to_roms_parts[roms_index] = "Imgs"

        # Imgs folder equal to roms path
        path = self.first_existing(
            os.path.join(os.sep.join(imgs_older_equal_to_roms_parts[:-1]), base_name)
        )
        if path:
            return path

        root_dir = os.sep.join(parts[:roms_index + 2])  # base path before Roms

        # Same dir as rom
        path = self.first_existing(os.path.join(root_dir, base_name))
        if path:
            return path

        # muOS SD2
        path = self.first_existing(
            os.path.join(
                "/mnt/sdcard/MUOS/info/catalogue/",
                rom_info.game_system.game_system_config.system_name,
                "box",
                base_name
            )
        )
        if path:
            return path

        # muOS SD1
        path = self.first_existing(
            os.path.join(
                "/mnt/mmc/MUOS/info/catalogue/",
                rom_info.game_system.game_system_config.system_name,
                "box",
                base_name
            )
        )
        if path:
            return path

        # ES format
        path = self.first_existing(
            os.path.join(root_dir, "Imgs", base_name + "-image")
        )
        if path:
            return path

        # ES format 2
        path = self.first_existing(
            os.path.join(root_dir, "Imgs", base_name + "-thumb")
        )
        if path:
            return path

        # ES format same folder
        path = self.first_existing(
            os.path.join(os.sep.join(imgs_older_equal_to_roms_parts[:-1]), base_name + "-image")
        )
        if path:
            return path

        # ES format 2 same folder
        path = self.first_existing(
            os.path.join(os.sep.join(imgs_older_equal_to_roms_parts[:-1]), base_name + "-thumb")
        )
        if path:
            return path


        #File itself is a png
        if rom_info.rom_file_path.lower().endswith(".png"):
            return rom_info.rom_file_path
        
        if(not prefer_savestate_screenshot):
            # Use RA savestate image
            save_state_image_path = Device.get_device().get_save_state_image(rom_info)
            if save_state_image_path is not None and CachedExists.exists(save_state_image_path):
                return save_state_image_path
        
        return None

    def _build_favorites_dict(self):
        favorites = Device.get_device().parse_favorites()
        favorite_paths = []
        for favorite in favorites:
            favorite_paths.append(str(Path(favorite.rom_path).resolve()))

        return favorite_paths

    def _get_favorite_icon(self, rom_info: RomInfo) -> str:
        if FavoritesManager.is_favorite(rom_info):
            return Theme.favorite_icon()
        else:
            return None
        

    def build_rom_list(self, game_system,filter: Callable[[str, str], bool] = lambda a,b: True, subfolder = None,
                       prefer_savestate_screenshot: bool = False) -> list[GridOrListEntry]:
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
                    display_name = RomFileNameUtils.get_rom_name_without_extensions(game_system,rom_file_path)

                rom_info = RomInfo(game_system,rom_file_path, display_name)

                file_rom_list.append(
                    GridOrListEntry(
                        primary_text=display_name,
                        description=game_system.folder_name, 
                        value=rom_info,
                        image_path_searcher= lambda rom_info=rom_info, game_entry=game_entry: self.get_image_path(rom_info, game_entry, prefer_savestate_screenshot=prefer_savestate_screenshot),
                        image_path_selected_searcher= lambda rom_info=rom_info, game_entry=game_entry: self.get_image_path(rom_info, game_entry, prefer_savestate_screenshot=prefer_savestate_screenshot),
                        icon_searcher=lambda rom_info=rom_info: self._get_favorite_icon(rom_info)
                    )
                )

        for rom_file_path in valid_folders:
            rom_file_name = os.path.basename(rom_file_path)
            game_entry = miyoo_game_list.get_by_file_path(rom_file_path)
            if(filter(rom_file_name, rom_file_path)):
                if(game_entry is not None):
                    display_name = game_entry.name
                else:
                    display_name = rom_file_name

                rom_info = RomInfo(game_system, rom_file_path, display_name)

                folder_rom_list.append(
                    GridOrListEntry(
                        primary_text=display_name,
                        description=game_system.folder_name, 
                        value=rom_info,
                        image_path_searcher= lambda rom_info=rom_info, game_entry=game_entry: self.get_image_path(rom_info, game_entry, prefer_savestate_screenshot=prefer_savestate_screenshot),
                        image_path_selected_searcher= lambda rom_info=rom_info, game_entry=game_entry: self.get_image_path(rom_info, game_entry, prefer_savestate_screenshot=prefer_savestate_screenshot),
                        icon_searcher=lambda rom_info=rom_info: self._get_favorite_icon(rom_info)
                    )
                )

        file_rom_list.sort(key=lambda entry: entry.get_primary_text())   
        folder_rom_list.sort(key=lambda entry: entry.get_primary_text())   

        return folder_rom_list + file_rom_list

_rom_select_options_builder_instance = None

def get_rom_select_options_builder():
    global _rom_select_options_builder_instance
    if _rom_select_options_builder_instance is None:
        _rom_select_options_builder_instance = RomSelectOptionsBuilder()
    return _rom_select_options_builder_instance