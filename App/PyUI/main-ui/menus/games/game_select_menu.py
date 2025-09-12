
import os
from pathlib import Path
from games.utils.game_entry import GameEntry
from menus.games.roms_menu_common import RomsMenuCommon
from menus.games.utils.collections_manager import CollectionsManager
from utils.py_ui_state import PyUiState
from views.grid_or_list_entry import GridOrListEntry
from games.utils.game_system import GameSystem 


class GameSelectMenu(RomsMenuCommon):
    def __init__(self):
        super().__init__()

    def _is_favorite(self, favorites: list[GameEntry], rom_file_path):
        return any(Path(rom_file_path).resolve() == Path(fav.rom_path).resolve() for fav in favorites)

    def _get_rom_list(self) -> list[GridOrListEntry]:
        return self.rom_select_options_builder.build_rom_list(self.game_system, subfolder=self.subfolder)

    def run_rom_selection(self,game_system : GameSystem, subfolder = None) :
        self.game_system = game_system
        self.subfolder = subfolder
        PyUiState.set_in_game_selection_screen(True)
        return_value = self._run_rom_selection(game_system.display_name)
        if(return_value is None and subfolder is None):
            PyUiState.set_in_game_selection_screen(False)
        return return_value
