
from pathlib import Path
from devices.device import Device
from games.utils.game_entry import GameEntry
from menus.games.roms_menu_common import RomsMenuCommon
from utils.consts import GAME_SELECT
from utils.py_ui_state import PyUiState
from views.grid_or_list_entry import GridOrListEntry
from games.utils.game_system import GameSystem 
from menus.games.utils.rom_select_options_builder import get_rom_select_options_builder

class GameSelectMenu(RomsMenuCommon):
    def __init__(self):
        super().__init__()

    def _is_favorite(self, favorites: list[GameEntry], rom_file_path):
        return any(Path(rom_file_path).resolve() == Path(fav.rom_path).resolve() for fav in favorites)

    def _get_rom_list(self) -> list[GridOrListEntry]:
        return get_rom_select_options_builder().build_rom_list(self.game_system, subfolder=self.subfolder, prefer_savestate_screenshot=self.prefer_savestate_screenshot())

    def run_rom_selection(self,game_system : GameSystem, subfolder = None) :
        self.game_system = game_system
        self.subfolder = subfolder
        PyUiState.set_in_game_selection_screen(True)
        return_value = self._run_rom_selection(game_system.display_name)
        if(return_value is None and subfolder is None):
            PyUiState.set_in_game_selection_screen(False)
        return return_value

    def prefer_savestate_screenshot(self):
        return Device.get_device().get_system_config().use_savestate_screenshots(GAME_SELECT)
