from menus.games.game_system_config import GameSystemConfig

class GameSystem:
    def __init__(self, folder_name, display_name, game_system_config : GameSystemConfig):
        self._folder_name = folder_name
        self._display_name = display_name
        self._game_system_config : GameSystemConfig = game_system_config

    @property
    def folder_name(self):
        return self._folder_name
    
    @property
    def display_name(self):
        return self._display_name
        
    @property
    def game_system_config(self) -> GameSystemConfig:
        return self._game_system_config
    