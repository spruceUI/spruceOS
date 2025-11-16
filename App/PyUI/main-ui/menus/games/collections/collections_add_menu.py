

import os
from controller.controller_inputs import ControllerInput
from display.on_screen_keyboard import OnScreenKeyboard
from menus.games.utils.collections_manager import CollectionsManager
from menus.games.utils.rom_info import RomInfo
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


from menus.language.language import Language

class CollectionsAddMenu():
    def __init__(self, rom_info : RomInfo):
        self.rom_info = rom_info

    def add_to_collection(self, collection_name):
        CollectionsManager.add_game_to_collection(collection_name, self.rom_info)

    def create_new_collection_and_add_to(self):
        collection_name = OnScreenKeyboard().get_input("Collection Name:")
        self.add_to_collection(collection_name)

    def build_options_list(self):
        option_list = []
        option_list.append(
                GridOrListEntry(
                        primary_text=Language.create_new_collection(),
                        value_text="",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=lambda input_value: self.create_new_collection_and_add_to()
                    )
            )
        
        collections_containing = CollectionsManager.get_collections_not_containing_rom(self.rom_info.rom_file_path)
        for collection_name in collections_containing:
            option_list.append(
                    GridOrListEntry(
                            primary_text="Add to " + collection_name,
                            value_text="",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                        value=lambda input_value, collection_name=collection_name: self.add_to_collection(collection_name)
                        )
                )
        return option_list

    def show_menu(self) :
        selected = Selection(None, None, 0)
        list_view = None
        while(selected is not None):
            option_list = self.build_options_list()
            
            if(list_view is None):
                list_view = ViewCreator.create_view(
                    view_type=ViewType.TEXT_ONLY,
                    top_bar_text=os.path.basename(self.rom_info.rom_file_path)[:25], 
                    options=option_list,
                    selected_index=selected.get_index())
            else:
                list_view.set_options(option_list)
    
            control_options = [ControllerInput.A]
            selected = list_view.get_selection(control_options)

            if(selected.get_input() in control_options):
                selected.get_selection().get_value()(selected.get_input())
                selected = None
            elif(ControllerInput.B == selected.get_input()):
                selected = None

