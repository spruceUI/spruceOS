import os
from pathlib import Path
import time

from menus.games.game_system_config import GameSystemConfig

class RomUtils:
    def __init__(self, roms_path):
        self.roms_path = roms_path

    def get_roms_path(self):
        return self.roms_path
    
    def _get_valid_suffix(self, system):
        game_system_config = GameSystemConfig(system)
        return game_system_config.get_extlist()

    def get_system_rom_directory(self, system):
        return os.path.join(self.roms_path, system)
    
    def get_roms(self, system):
        directory = self.get_system_rom_directory(system)
        valid_suffix_set = self._get_valid_suffix(system)
        if(len(valid_suffix_set) == 0):
            valid_files = sorted(
                entry.path for entry in os.scandir(directory)
                if entry.is_file(follow_symlinks=False)
                and not entry.name.startswith('.')
                and not entry.name.endswith(('.xml', '.txt', '.db'))
            )
        else:
            valid_files = sorted(
                entry.path for entry in os.scandir(directory)
                if entry.is_file(follow_symlinks=False)
                and Path(entry.name).suffix.lower() in valid_suffix_set
            )

        return valid_files
