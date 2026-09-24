import json
import os
import tempfile
import threading
from typing import List, Optional

from menus.games.utils.rom_info import RomInfo
from utils.logger import PyUiLogger


class CheevosCacheEntry:
    def __init__(self, rom_file_path, game_system_name, display_name=None, game_id=None):
        self.rom_file_path = rom_file_path
        self.game_system_name = game_system_name
        self.display_name = display_name
        self.game_id = game_id


class CheevosCacheManager:
    _entries_file: Optional[str] = None
    _entries: List[CheevosCacheEntry] = []
    _paths = set()
    _lock = threading.Lock()
    _init_event = threading.Event()

    @classmethod
    def initialize(cls, entries_file: str):
        cls._entries_file = entries_file
        cls._entries = cls._load()
        cls._paths = {e.rom_file_path for e in cls._entries}
        cls._init_event.set()

    @classmethod
    def _wait_for_init(cls):
        cls._init_event.wait()

    @classmethod
    def _load(cls) -> List[CheevosCacheEntry]:
        if not cls._entries_file or not os.path.exists(cls._entries_file):
            return []
        try:
            with open(cls._entries_file, 'r') as f:
                data = json.load(f)
            return [
                CheevosCacheEntry(
                    e.get("rom_file_path"),
                    e.get("game_system_name"),
                    e.get("display_name"),
                    e.get("game_id"),
                )
                for e in data if e.get("rom_file_path")
            ]
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to read {cls._entries_file}: {e}")
            return []

    @classmethod
    def _save(cls):
        cls._paths = {e.rom_file_path for e in cls._entries}
        tempname = None
        try:
            dirpath = os.path.dirname(cls._entries_file) or "."
            with tempfile.NamedTemporaryFile(
                'w', dir=dirpath,
                prefix=os.path.basename(cls._entries_file) + ".",
                suffix=".tmp", delete=False
            ) as tmp:
                tempname = tmp.name
                json.dump([e.__dict__ for e in cls._entries], tmp, indent=4)
                tmp.flush()
                os.fsync(tmp.fileno())
            os.replace(tempname, cls._entries_file)
            tempname = None
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to save {cls._entries_file}: {e}")
        finally:
            if tempname is not None:
                try:
                    os.remove(tempname)
                except OSError:
                    pass

    @staticmethod
    def parse_result(lines):
        for line in reversed(lines):
            try:
                parsed = json.loads(line)
            except ValueError:
                continue
            return parsed.get("message"), parsed.get("game_id")
        return (lines[-1] if lines else "No response"), None

    @classmethod
    def add_cached(cls, rom_info: RomInfo, game_id=None):
        cls._wait_for_init()
        with cls._lock:
            cls._entries = [e for e in cls._entries
                            if e.rom_file_path != rom_info.rom_file_path]
            cls._entries.append(CheevosCacheEntry(
                rom_info.rom_file_path,
                rom_info.game_system.system_name,
                rom_info.display_name,
                game_id,
            ))
            cls._save()

    @classmethod
    def set_game_id(cls, rom_file_path: str, game_id):
        cls._wait_for_init()
        with cls._lock:
            for e in cls._entries:
                if e.rom_file_path == rom_file_path:
                    e.game_id = game_id
            cls._save()

    @classmethod
    def remove_cached(cls, rom_file_path: str):
        cls._wait_for_init()
        with cls._lock:
            cls._entries = [e for e in cls._entries if e.rom_file_path != rom_file_path]
            cls._save()

    @classmethod
    def is_cached(cls, rom_info: RomInfo) -> bool:
        cls._wait_for_init()
        return rom_info.rom_file_path in cls._paths

    @classmethod
    def get_cached(cls) -> List[CheevosCacheEntry]:
        cls._wait_for_init()
        return list(cls._entries)
