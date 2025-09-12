import os
from menus.games.file_based_game_system_config import FileBasedGameSystemConfig

class GameSystem:
    def __init__(self, folder_path, display_name, game_system_config : FileBasedGameSystemConfig):
        self._folder_path = folder_path
        self._display_name = display_name
        self._game_system_config : FileBasedGameSystemConfig = game_system_config

    @property
    def folder_name(self):
        return os.path.basename(self._folder_path)

    @property
    def folder_path(self):
        return self._folder_path
    
    @property
    def display_name(self):
        return self._display_name
        
    @property
    def game_system_config(self) -> FileBasedGameSystemConfig:
        return self._game_system_config
    