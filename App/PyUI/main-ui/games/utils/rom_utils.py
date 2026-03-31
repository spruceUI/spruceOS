import os
from pathlib import Path

from devices.device import Device
from games.utils.game_system import GameSystem
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

        self._get_roms_cache: dict[tuple, tuple[list[str], list[str]]] = {}

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
        system_dir = os.path.join(self.roms_path, self.get_roms_dir_for_emu_dir(system))
        for name in ("miyoogamelist.xml", "gamelist.xml"):
            path = os.path.join(system_dir, name)
            if os.path.isfile(path):
                return path
        return ""

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
                        if (entry.is_dir(follow_symlinks=False) and game_system.game_system_config.scan_subfolders()):
                            if(self.has_roms(game_system, directory=entry)):
                                return True
                        continue

                    if len(valid_suffix_set) == 0:
                        if not entry.name.startswith('.') and not entry.name.endswith(('.xml', '.txt', '.db')) and not entry.name in game_system.game_system_config.get_ignore_list():
                            return True
                    else:
                        if Path(entry.name).suffix.lower() in valid_suffix_set:
                            return True

            except Exception as e:
                PyUiLogger.get_logger().error(f"Error scanning directory '{dir_to_search}': {e}")

        return False # No valid files found

    def get_roms(self, game_system: GameSystem, directory=None):
        cache_key = (game_system, directory)
        if cache_key in self._get_roms_cache:
            return self._get_roms_cache[cache_key]

        directories_to_search = [directory] if directory else game_system.folder_paths
        valid_files = []
        valid_folders = []

        config = game_system.game_system_config
        valid_suffix_set = {s.lower() for s in config.get_extlist()}
        ignore_set = set(config.get_ignore_list())
        scan_subfolders = config.scan_subfolders()
        
        for dir_to_search in directories_to_search:
            for root, dirs, files in os.walk(dir_to_search, topdown=True):
                # Skip "Imgs" directories
                dirs[:] = [d for d in dirs if d != "Imgs" and not d.startswith('.')]

                # Files
                for name in files:
                    if name.startswith('.'):
                        continue
                    suffix = Path(name).suffix.lower()
                    if (not valid_suffix_set and not name.endswith(('.xml', '.txt', '.db'))) or suffix in valid_suffix_set:
                        if name not in ignore_set:
                            valid_files.append(os.path.join(root, name))

                # Folders
                if scan_subfolders:
                    for d in dirs:
                        dir_path = os.path.join(root, d)
                        roms_in_dir, valid_folders = self.get_roms(game_system, dir_path)
                        if(len(roms_in_dir) > 0 or len(valid_folders) > 0):
                            PyUiLogger.get_logger().info(f"found {roms_in_dir} in {dir_path}")
                            valid_folders.append(os.path.join(root, dir_path))


                # If not scanning subfolders, break after the top directory
                if not scan_subfolders:
                    break

        # Cache the result if supported
        if Device.get_device().supports_caching_rom_lists():
            self._get_roms_cache[cache_key] = (valid_files, valid_folders)

        return valid_files, valid_folders