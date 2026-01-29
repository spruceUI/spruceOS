import os
from menus.games.file_based_game_system_config import FileBasedGameSystemConfig

class GameSystem:
    def __init__(self, folder_paths, display_name, game_system_config : FileBasedGameSystemConfig):
        self._folder_paths = tuple(folder_paths)
        self._display_name = display_name
        self._game_system_config : FileBasedGameSystemConfig = game_system_config

    @property
    def folder_name(self):
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
    def brand(self):
        return self._game_system_config.get_brand()
    
    @property
    def type(self):
        return self._game_system_config.get_type()
    
    @property
    def release_year(self):
        return self._game_system_config.get_release_year()
        
    @property
    def game_system_config(self) -> FileBasedGameSystemConfig:
        return self._game_system_config
    
    # Equality: two systems are equal if their folder_paths are the same
    def __eq__(self, other):
        if not isinstance(other, GameSystem):
            return False
        return self._folder_paths == other._folder_paths

    # Hash: use folder_paths tuple
    def __hash__(self):
        return hash(self._folder_paths)