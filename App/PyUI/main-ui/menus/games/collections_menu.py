
import os
import subprocess
from devices.device import Device
from menus.games.roms_menu_common import RomsMenuCommon
from menus.games.utils.collections_manager import CollectionsManager
from menus.games.utils.favorites_manager import FavoritesManager
from menus.games.utils.rom_info import RomInfo
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry


class CollectionsMenu(RomsMenuCommon):
    def __init__(self, current_collection = None):
        super().__init__()
        self.current_collection = current_collection
        PyUiLogger.get_logger().info("CollectionsMenu.init(" + str(self.current_collection) +")")

    def _get_rom_list(self) -> list[GridOrListEntry]:
        PyUiLogger.get_logger().info("_get_rom_list self.current_collection = " + str(self.current_collection) +")")
        if(self.current_collection is None):
            rom_list = []
            collections = CollectionsManager.get_collection_names()
            for collection in collections:
                rom_info = RomInfo(None, collection, is_collection=True)
                # Get the base filename without extension
                img_path = os.path.join(Device.get_collections_path(),"Imgs",collection+".png")

                rom_list.append(
                    GridOrListEntry(
                        primary_text=collection,
                        image_path=img_path,
                        image_path_selected=img_path,
                        description="Collections", 
                        icon=None,
                        value=rom_info)
                )
            return rom_list
        else:
            return self.build_rom_selection_for_collection(self.current_collection)

    def run_rom_selection(self) :
        return self._run_rom_selection("Collections")

    #def _run_subfolder_menu(self, rom_info : RomInfo) -> list[GridOrListEntry]:
    #    if(self.current_collection is None):
    #        rom_list = CollectionsManager.get_games_in_collection(rom_info.rom_file_path)
    #        return CollectionsMenu(rom_info.rom_file_path)._run_rom_selection_for_rom_list(rom_info.rom_file_path, rom_list)
    #    else:
    #s        return None

    def _menu_pressed(self, selection):
        if(selection.is_collection):
            pass        
        else:
            super()._menu_pressed(selection)