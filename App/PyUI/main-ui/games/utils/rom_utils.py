import os
from pathlib import Path
import time

from menus.games.game_system_config import GameSystemConfig
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

    def get_roms_path(self):
        return self.roms_path
    
    def get_roms_dir_for_emu_dir(self, emu_dir):
        # Could read config.json but don't want to waste time
        # It's only a fixed list we can add to as needed
        return self.emu_dir_to_rom_dir_non_matching.get(emu_dir,emu_dir)

    def _get_valid_suffix(self, system):
        game_system_config = GameSystemConfig(system)
        return game_system_config.get_extlist()

    def get_system_rom_directory(self, system):
        return os.path.join(self.roms_path, self.get_roms_dir_for_emu_dir(system))
    
    def has_roms(self, system, directory = None):
        if(directory is None):
            directory = self.get_system_rom_directory(system)

        if os.path.basename(directory) == "Imgs":
            return False

        valid_suffix_set = self._get_valid_suffix(system)

        try:
            for entry in os.scandir(directory):
                if not entry.is_file(follow_symlinks=False):
                    if (entry.is_dir(follow_symlinks=False) and system not in self.dont_scan_subfolders):
                        if(self.has_roms(system, directory=entry)):
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
            PyUiLogger.get_logger().error(f"Error scanning directory '{directory}': {e}")
            return False
    
    def get_roms(self, system, directory = None):
        if(directory is None):
            directory = self.get_system_rom_directory(system)

        if os.path.basename(directory) == "Imgs":
            return []
        
        valid_suffix_set = self._get_valid_suffix(system)
        valid_files = []
        valid_folders = []

        for entry in os.scandir(directory):
            if entry.is_file(follow_symlinks=False):
                if not entry.name.startswith('.') and (
                    len(valid_suffix_set) == 0 and not entry.name.endswith(('.xml', '.txt', '.db'))
                    or Path(entry.name).suffix.lower() in valid_suffix_set
                ):
                    valid_files.append(entry.path)
            elif entry.is_dir(follow_symlinks=False):
                if self.has_roms(system, entry.path):
                    valid_folders.append(entry.path)

        # Combine and sort once at the end
        valid_files = sorted(valid_folders) + sorted(valid_files)

        return valid_files
