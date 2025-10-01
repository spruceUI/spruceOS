
import threading
from typing import List, Optional
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.roms_list_manager import RomsListManager

class FavoritesManager:
    _favoritesManager = Optional[RomsListManager]
    _init_event = threading.Event()  # signals when initialize() has been called

    @classmethod
    def initialize(cls, favorites_path: str):
        cls._favoritesManager = RomsListManager(favorites_path)
        cls._init_event.set()  # unblock waiting methods
    
    @classmethod
    def _wait_for_init(cls):
        cls._init_event.wait()  # blocks until initialize() happens


    @classmethod
    def add_favorite(cls, rom_info: RomInfo):
        cls._wait_for_init()
        cls._favoritesManager.add_game(rom_info)

    @classmethod
    def remove_favorite(cls, rom_info: RomInfo):
        cls._wait_for_init()
        cls._favoritesManager.remove_game(rom_info)

    @classmethod
    def is_favorite(cls, rom_info: RomInfo) -> bool:
        cls._wait_for_init()
        return cls._favoritesManager.is_on_list(rom_info)

    @classmethod
    def get_favorites(cls) -> List[RomInfo]:
        cls._wait_for_init()
        return cls._favoritesManager.get_games()

    @classmethod
    def sort_favorites_alphabetically(cls):
        cls._wait_for_init()
        return cls._favoritesManager.sort_alphabetically()
