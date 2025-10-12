import os
from menus.games.file_based_game_system_config import FileBasedGameSystemConfig

class GameSystem:
    def __init__(self, folder_paths, display_name, game_system_config : FileBasedGameSystemConfig):
        self._folder_paths = folder_paths
        self._display_name = display_name
        self._game_system_config : FileBasedGameSystemConfig = game_system_config

    @property
    def folder_name(self):
        #TODO how to handle, does it matter?
        return os.path.basename(self._folder_paths[0])

    @property
    def folder_paths(self):
        return self._folder_paths
    
    @property
    def display_name(self):
        return self._display_name
    
    @property
    def sort_order(self):
        return self._game_system_config.get_sort_order()
        
    @property
    def game_system_config(self) -> FileBasedGameSystemConfig:
        return self._game_system_config
    