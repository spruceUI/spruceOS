import os
from pathlib import Path

from devices.device import Device
from games.utils.game_system import GameSystem
from games.utils.rom_list_verifier import RomListVerifier
from menus.games.file_based_game_system_config import FileBasedGameSystemConfig
from utils.logger import PyUiLogger
import os
import json
import threading
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

        # directory -> (folder date it was read at, game files, subfolders)
        self._get_roms_cache: dict[str, tuple[float, list[str], list[str]]] = {}
        self._cache_lock = threading.Lock()

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
        except (FileNotFoundError, json.JSONDecodeError, KeyError, OSError):
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


    def _scan_directory(self, game_system: GameSystem, dir_to_search):
        """
        Read a single directory and work out which entries count as games.

        Uses scandir rather than listdir so the file/directory answer comes back
        as part of the directory read instead of costing a separate lookup per
        entry. On a folder holding a few thousand games that is the difference
        between one read and several thousand, which matters on these devices.
        """
        config = game_system.game_system_config
        valid_suffix_set = {s.lower() for s in config.get_extlist()}
        ignore_set = set(config.get_ignore_list())
        scan_subfolders = config.scan_subfolders()

        valid_files = []
        valid_folders = []

        try:
            with os.scandir(dir_to_search) as entries:
                for entry in entries:
                    name = entry.name

                    if name.startswith('.'):
                        continue

                    try:
                        # follow_symlinks stays on to match the os.path.isdir this
                        # replaced, so symlinked rom folders keep working
                        is_dir = entry.is_dir()
                    except OSError:
                        is_dir = False

                    if is_dir:
                        if not scan_subfolders:
                            continue
                        if name == "Imgs":
                            continue

                        roms_sub, folders_sub = self.get_roms(game_system, entry.path)

                        if roms_sub or folders_sub:
                            valid_folders.append(entry.path)

                    else:
                        dot = name.rfind('.')
                        suffix = name[dot:].lower() if dot != -1 else ''

                        if (not valid_suffix_set and not name.endswith(('.xml', '.txt', '.db'))) or suffix in valid_suffix_set:
                            if name not in ignore_set:
                                valid_files.append(entry.path)
        except OSError:
            return valid_files, valid_folders

        return valid_files, valid_folders

    def _read_cache(self, dir_to_search, dir_mtime):
        """
        The cached listing for a directory, or None if we have nothing usable.

        A folder date that has moved is a reliable sign the folder changed, so we
        rescan on the spot. A date that hasn't moved proves nothing -- that is
        what _verify_cached_listing sorts out afterwards.
        """
        with self._cache_lock:
            cached = self._get_roms_cache.get(dir_to_search)

        if cached is not None and cached[0] == dir_mtime:
            return cached[1], cached[2]

        if not Device.get_device().supports_caching_rom_lists():
            return None

        on_disk = self._load_disk_cache(dir_to_search, dir_mtime)

        if on_disk is not None:
            with self._cache_lock:
                self._get_roms_cache[dir_to_search] = (dir_mtime, on_disk[0], on_disk[1])

        return on_disk

    def _write_cache(self, dir_to_search, dir_mtime, files, folders):
        if not Device.get_device().supports_caching_rom_lists():
            return

        with self._cache_lock:
            self._get_roms_cache[dir_to_search] = (dir_mtime, files, folders)

        self._save_disk_cache(dir_to_search, dir_mtime, files, folders)

    def _verify_cached_listing(self, game_system: GameSystem, dir_to_search):
        """
        Re-read a directory we served from cache and correct the cache if what we
        handed the menu no longer matches what is actually there. Runs on the
        RomListVerifier worker thread; returns True when the listing was wrong.
        """
        try:
            dir_mtime = os.path.getmtime(dir_to_search)
        except OSError:
            return False

        files, folders = self._scan_directory(game_system, dir_to_search)

        with self._cache_lock:
            cached = self._get_roms_cache.get(dir_to_search)

        # Compare against the listing we served, whatever date it was stored
        # under -- a date that shifted underneath us is not itself a change.
        # Compared as sets because the order a directory reads back in can change
        # on its own, and the menu sorts the list anyway.
        if (cached is not None
                and set(cached[1]) == set(files)
                and set(cached[2]) == set(folders)):
            if cached[0] != dir_mtime:
                self._write_cache(dir_to_search, dir_mtime, files, folders)
            return False

        self._write_cache(dir_to_search, dir_mtime, files, folders)
        return True

    def get_roms(self, game_system: GameSystem, directory=None):
        directories_to_search = [directory] if directory else game_system.folder_paths

        all_valid_files = []
        all_valid_folders = []

        for dir_to_search in directories_to_search:
            try:
                dir_mtime = os.path.getmtime(dir_to_search)
            except OSError:
                continue

            cached = self._read_cache(dir_to_search, dir_mtime)

            if cached is not None:
                files, folders = cached
                all_valid_files.extend(files)
                all_valid_folders.extend(folders)

                # The folder's date can't be trusted on its own -- archive tools
                # rewrite it after extracting -- so confirm the listing in the
                # background and let the menus know if it was stale.
                RomListVerifier.schedule(
                    dir_to_search,
                    lambda d=dir_to_search: self._verify_cached_listing(game_system, d),
                )
                continue

            valid_files, valid_folders = self._scan_directory(game_system, dir_to_search)
            self._write_cache(dir_to_search, dir_mtime, valid_files, valid_folders)

            all_valid_files.extend(valid_files)
            all_valid_folders.extend(valid_folders)

        return all_valid_files, all_valid_folders