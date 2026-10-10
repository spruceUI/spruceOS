import threading
from typing import List

from menus.games.utils import raproxy_cli
from menus.games.utils.rom_info import RomInfo


class CheevosCacheEntry:
    def __init__(self, game_id, title, unlocks=None, rom_path=None):
        self.game_id = game_id
        self.title = title
        self.unlocks = unlocks
        self.rom_path = rom_path


class CheevosCacheManager:
    _entries: List[CheevosCacheEntry] = []
    _rom_paths = set()
    _loaded = threading.Event()

    @classmethod
    def initialize(cls):
        threading.Thread(target=cls.refresh, daemon=True).start()

    @classmethod
    def refresh(cls):
        games = raproxy_cli.run_json("cached-games", "--json") if raproxy_cli.enabled() else None
        entries = [
            CheevosCacheEntry(g.get("game_id"), g.get("title"), g.get("unlocks"), g.get("rom_path"))
            for g in games or [] if isinstance(g, dict) and g.get("game_id") is not None
        ]
        cls._entries = entries
        cls._rom_paths = {e.rom_path for e in entries if e.rom_path}
        cls._loaded.set()

    @classmethod
    def is_cached(cls, rom_info: RomInfo) -> bool:
        cls._loaded.wait(5)
        return bool(cls._rom_paths) and raproxy_cli.rom_key(rom_info.rom_file_path) in cls._rom_paths

    @classmethod
    def get_cached(cls) -> List[CheevosCacheEntry]:
        cls._loaded.wait(30)
        return list(cls._entries)
