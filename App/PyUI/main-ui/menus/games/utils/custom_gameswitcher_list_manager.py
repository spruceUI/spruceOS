
import threading
from typing import List, Optional
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.roms_list_manager import RomsListManager
from utils.py_ui_config import PyUiConfig

class CustomGameSwitcherListManager:
    _recentsManager = Optional[RomsListManager]
    _exists = False
    _init_event = threading.Event()  # signals when initialize() has been called

    @classmethod
    def initialize(cls):
        if(PyUiConfig.get_gameswitcher_path() is not None):
            cls._recentsManager = RomsListManager(PyUiConfig.get_gameswitcher_path())
            cls._exists = True
        cls._init_event.set()  # unblock waiting methods

    @classmethod
    def _wait_for_init(cls):
        cls._init_event.wait()  # blocks until initialize() happens

    @classmethod
    def add_game(cls, rom_info: RomInfo):
        cls._wait_for_init()
        if(cls._exists):
            cls._recentsManager.add_game(rom_info)
            games = cls._recentsManager.get_games()
            if len(games) > 20:
                for game in games[20:]:
                    cls._recentsManager.remove_game(game)
                
    @classmethod
    def get_recents(cls) -> List[RomInfo]:
        cls._wait_for_init()
        if(cls._exists):
            return cls._recentsManager.get_games()
        else:
            return []
        
    @classmethod
    def contains_game(cls, rom_info: RomInfo) -> bool:
        cls._wait_for_init()
        if(cls._exists):
            return cls._recentsManager.is_on_list(rom_info)
        else:
            return False  
              
    @classmethod
    def remove_game(cls, rom_info: RomInfo) -> bool:
        cls._wait_for_init()
        if(cls._exists):
            return cls._recentsManager.remove_game(rom_info)
        else:
            return False