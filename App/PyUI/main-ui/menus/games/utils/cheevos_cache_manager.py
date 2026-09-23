import threading
from typing import List, Optional
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.roms_list_manager import RomsListManager

class CheevosCacheManager:
    _cheevosCacheManager = Optional[RomsListManager]
    _init_event = threading.Event()

    @classmethod
    def initialize(cls, cheevos_cache_path: str):
        cls._cheevosCacheManager = RomsListManager(cheevos_cache_path)
        cls._init_event.set()

    @classmethod
    def _wait_for_init(cls):
        cls._init_event.wait()

    @classmethod
    def add_cached(cls, rom_info: RomInfo):
        cls._wait_for_init()
        cls._cheevosCacheManager.add_game(rom_info)

    @classmethod
    def remove_cached(cls, rom_info: RomInfo):
        cls._wait_for_init()
        cls._cheevosCacheManager.remove_game(rom_info)

    @classmethod
    def is_cached(cls, rom_info: RomInfo) -> bool:
        cls._wait_for_init()
        return cls._cheevosCacheManager.is_on_list(rom_info)

    @classmethod
    def get_cached(cls) -> List[RomInfo]:
        cls._wait_for_init()
        return cls._cheevosCacheManager.get_games()
