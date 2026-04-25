
from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.games.roms_menu_common import RomsMenuCommon
from menus.games.utils.favorites_manager import FavoritesManager
from menus.games.utils.rom_file_name_utils import RomFileNameUtils
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.rom_select_options_builder import get_rom_select_options_builder
from utils.consts import FAVORITES
from views.grid_or_list_entry import GridOrListEntry
from menus.language.language import Language
from views.rom_grid_or_list_entry import RomGridOrListEntry

class FavoritesMenu(RomsMenuCommon):
    def __init__(self):
        super().__init__()

    def _get_rom_list(self) -> list[GridOrListEntry]:
        rom_list = []
        favorites : list[RomInfo] = FavoritesManager.get_favorites()
        get_image_path_fn = get_rom_select_options_builder().get_image_path
        for rom_info in favorites:
            display_name = rom_info.display_name
            if(display_name is None):
                display_name =  RomFileNameUtils.get_rom_name_without_extensions(rom_info.game_system, rom_info.rom_file_path)

            rom_list.append(
                RomGridOrListEntry(
                        display_name=display_name  +" (" + self._extract_game_system(rom_info.rom_file_path)+")",
                        folder_name="Recents",
                        game_system=rom_info.game_system,
                        rom_file_path=rom_info.rom_file_path,
                        game_entry=None,
                        prefer_savestate_screenshot=self.prefer_savestate_screenshot(),
                        get_image_path_fn=get_image_path_fn,
                        get_favorite_icon=None
                )
            )
        return rom_list

    def run_rom_selection(self) :
        return self._run_rom_selection("Favorites")

    def sort_favorites_alphabetically(self, input_value):
        if(ControllerInput.A == input_value):
            FavoritesManager.sort_favorites_alphabetically()

    def get_additional_menu_options(self):
        popup_options = []
        popup_options.append(GridOrListEntry(
            primary_text=Language.sort_favorites(),
            description=None,
            image_path=None,
            image_path_selected=None,
            icon=None,
            value=lambda input_value: self.sort_favorites_alphabetically(input_value)
        ))
        return popup_options
        
    def prefer_savestate_screenshot(self):
        return Device.get_device().get_system_config().use_savestate_screenshots(FAVORITES)
