import os
from pathlib import Path
import time

from menus.games.file_based_game_system_config import FileBasedGameSystemConfig
from utils.logger import PyUiLogger

class RomUtils:
    def __init__(self, roms_path):
        self.roms_path = roms_path
        self.emu_dir_to_rom_dir_non_matching = {
            "PPSSPP": "PSP",
            "FFPLAY":"FFMPEG",
            "MPV":"FFMPEG",
            "WSC":"WS"
        }

        self.dont_scan_subfolders = ["PORTS","PORTS32","PORTS64","PM"]
    
    def get_roms_dir_for_emu_dir(self, emu_dir):
        # Could read config.json but don't want to waste time
        # It's only a fixed list we can add to as needed
        return self.emu_dir_to_rom_dir_non_matching.get(emu_dir,emu_dir)

    def _get_valid_suffix(self, system):
        game_system_config = FileBasedGameSystemConfig(system)
        return game_system_config.get_extlist()

    #TODO do a git system device file so we can geneically
    #support other formats/systems
    def get_miyoo_games_file(self,system):
        return os.path.join(self.roms_path, self.get_roms_dir_for_emu_dir(system),"miyoogamelist.xml")

    def has_roms(self, game_system, directory = None):
        directories_to_search = []
        if(directory is None):
            directories_to_search = game_system.folder_paths
        else:
            directories_to_search = [directory]

        for dir_to_search in directories_to_search:
            if os.path.basename(dir_to_search) == "Imgs":
                break

            valid_suffix_set = game_system.game_system_config.get_extlist()

            try:
                for entry in os.scandir(dir_to_search):
                    if not entry.is_file(follow_symlinks=False):
                        if (entry.is_dir(follow_symlinks=False) and game_system.game_system_config.get_label() not in self.dont_scan_subfolders):
                            if(self.has_roms(game_system, directory=entry)):
                                return True
                        continue

                    if len(valid_suffix_set) == 0:
                        if not entry.name.startswith('.') and not entry.name.endswith(('.xml', '.txt', '.db')):
                            return True
                    else:
                        if Path(entry.name).suffix.lower() in valid_suffix_set:
                            return True

                return False  # No valid files found
            except Exception as e:
                PyUiLogger.get_logger().error(f"Error scanning directory '{dir_to_search}': {e}")

        return False
    
    def get_roms(self, game_system, directory = None):
        directories_to_search = []
        if(directory is None):
            directories_to_search = game_system.folder_paths
        else:
            directories_to_search = [directory]
       
        valid_files = []
        valid_folders = []

        for dir_to_search in directories_to_search:
            if os.path.basename(dir_to_search) == "Imgs":
                return []
            
            valid_suffix_set = game_system.game_system_config.get_extlist()

            for entry in os.scandir(dir_to_search):
                if entry.is_file(follow_symlinks=False):
                    if not entry.name.startswith('.') and (
                        len(valid_suffix_set) == 0 and not entry.name.endswith(('.xml', '.txt', '.db'))
                        or Path(entry.name).suffix.lower() in valid_suffix_set
                    ):
                        valid_files.append(entry.path)
                elif entry.is_dir(follow_symlinks=False):
                    if self.has_roms(game_system, entry.path):
                        valid_folders.append(entry.path)


        return valid_files, valid_folders
