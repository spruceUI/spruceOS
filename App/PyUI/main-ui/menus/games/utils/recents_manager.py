
import threading
from typing import List, Optional
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.roms_list_manager import RomsListManager

class RecentsManager:
    _recentsManager: Optional[RomsListManager] = None
    _init_event = threading.Event()  # signals when initialize() has been called

    @classmethod
    def initialize(cls, recents_path: str):
        cls._recentsManager = RomsListManager(recents_path)
        cls._init_event.set()  # unblock waiting methods

    @classmethod
    def _wait_for_init(cls):
        cls._init_event.wait()  # blocks until initialize() happens

    @classmethod
    def add_game(cls, rom_info: RomInfo):
        cls._wait_for_init()
        manager = cls._recentsManager
        if manager is None:
            return
        manager.add_game(rom_info)
        games = manager.get_games()
        if len(games) > 20:
            for game in games[20:]:
                manager.remove_game(game)
                
    @classmethod
    def get_recents(cls) -> List[RomInfo]:
        cls._wait_for_init()
        manager = cls._recentsManager
        if manager is None:
            return []
        return manager.get_games()


    @classmethod
    def remove_game(cls, rom_info: RomInfo):
        cls._wait_for_init()
        manager = cls._recentsManager
        if manager is None:
            return
        manager.remove_game(rom_info)
