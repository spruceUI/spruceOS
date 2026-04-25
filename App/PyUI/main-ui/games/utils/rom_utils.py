import os
from pathlib import Path

from devices.device import Device
from games.utils.game_system import GameSystem
from menus.games.file_based_game_system_config import FileBasedGameSystemConfig
from utils.logger import PyUiLogger
import os
import json
from pathlib import Path

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

    def get_cache_dir(self):
        return os.path.join(Device.get_device().get_saves_dir(),"cache")

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


    def _get_cache_file(self,directory):
        safe_name = directory.replace("/", "_").replace("\\", "_")
        return os.path.join(self.get_cache_dir(), f"{safe_name}.json")


    def _load_disk_cache(self,directory, mtime):
        cache_file = self._get_cache_file(directory)

        try:
            with open(cache_file, "r") as f:
                data = json.load(f)

            if data.get("mtime") == mtime:
                return data["files"], data["folders"]
            else:
                PyUiLogger.get_logger().info(f"Folder update detected [{directory}]")
        except (FileNotFoundError, json.JSONDecodeError):
            pass

        return None


    def _save_disk_cache(self,directory, mtime, files, folders):
        os.makedirs(self.get_cache_dir(), exist_ok=True)
        cache_file = self._get_cache_file(directory)

        with open(cache_file, "w") as f:
            json.dump({
                "mtime": mtime,
                "files": files,
                "folders": folders
            }, f)


    def get_roms(self, game_system: GameSystem, directory=None):
        directories_to_search = [directory] if directory else game_system.folder_paths

        all_valid_files = []
        all_valid_folders = []

        config = game_system.game_system_config
        valid_suffix_set = {s.lower() for s in config.get_extlist()}
        ignore_set = set(config.get_ignore_list())
        scan_subfolders = config.scan_subfolders()

        for dir_to_search in directories_to_search:
            try:
                dir_mtime = os.path.getmtime(dir_to_search)
            except OSError:
                continue

            cache_key = (dir_to_search, dir_mtime)

            # --- In-memory cache ---
            if cache_key in self._get_roms_cache:
                files, folders = self._get_roms_cache[cache_key]
                all_valid_files.extend(files)
                all_valid_folders.extend(folders)
                continue

            # --- Disk cache ---
            if Device.get_device().supports_caching_rom_lists():
                cached = self._load_disk_cache(dir_to_search, dir_mtime)
                if cached:
                    self._get_roms_cache[cache_key] = cached
                    files, folders = cached
                    all_valid_files.extend(files)
                    all_valid_folders.extend(folders)
                    continue

            # --- Fresh scan ---
            valid_files = []
            valid_folders = []

            try:
                entries = os.listdir(dir_to_search)
            except OSError:
                continue

            for name in entries:
                if name.startswith('.'):
                    continue

                full_path = os.path.join(dir_to_search, name)

                if os.path.isdir(full_path):
                    if not scan_subfolders:
                        continue
                    if name == "Imgs":
                        continue

                    roms_sub, folders_sub = self.get_roms(game_system, full_path)

                    if roms_sub or folders_sub:
                        valid_folders.append(full_path)

                else:
                    suffix = Path(name).suffix.lower()

                    if (not valid_suffix_set and not name.endswith(('.xml', '.txt', '.db'))) or suffix in valid_suffix_set:
                        if name not in ignore_set:
                            valid_files.append(full_path)

            result = (valid_files, valid_folders)

            # --- Save caches ---
            if Device.get_device().supports_caching_rom_lists():
                self._get_roms_cache[cache_key] = result
                self._save_disk_cache(dir_to_search, dir_mtime, valid_files, valid_folders)

            all_valid_files.extend(valid_files)
            all_valid_folders.extend(valid_folders)

        return all_valid_files, all_valid_folders