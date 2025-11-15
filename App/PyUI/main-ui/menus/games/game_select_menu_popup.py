

import os
import random
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from display.on_screen_keyboard import OnScreenKeyboard
from menus.games.collections.collections_management_menu import CollectionsManagementMenu
from menus.games.utils.favorites_manager import FavoritesManager
from menus.games.utils.rom_info import RomInfo
from themes.theme import Theme
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType


class GameSelectMenuPopup:
    def __init__(self):
        pass

    def add_favorite(self, rom_info : RomInfo, input_value):
        FavoritesManager.add_favorite(rom_info)

    def remove_favorite(self, rom_info : RomInfo, input_value):
        FavoritesManager.remove_favorite(rom_info)
    
    def collections_management_view(self, rom_info : RomInfo, input_value):
        CollectionsManagementMenu(rom_info).show_menu()


    def launch_random_game(self, input_value, rom_list):
        if ControllerInput.A != input_value:
            return

        # Filter out directories
        roms_only = [rom for rom in rom_list if not os.path.isdir(rom.get_value().rom_file_path)]

        if not roms_only:
            Display.display_message("No valid ROMs available to launch.", duration_ms=2000)
            return

        selected_rom = random.choice(roms_only)
        Device.run_game(selected_rom.get_value())

    def execute_game_search(self, game_system, input_value):
        from menus.games.search_games_for_system_menu import SearchGamesForSystemMenu
        search_txt = OnScreenKeyboard().get_input("Game Search:")
        if(search_txt is not None):
            return SearchGamesForSystemMenu(game_system, search_txt.upper()).run_rom_selection()

    def toggle_view(self):
        if(ViewType.TEXT_AND_IMAGE == Theme.get_game_selection_view_type()):
            Theme.set_game_selection_view_type(ViewType.GRID)
        elif(ViewType.GRID == Theme.get_game_selection_view_type()):
            Theme.set_game_selection_view_type(ViewType.CAROUSEL)
        else:
            Theme.set_game_selection_view_type(ViewType.TEXT_AND_IMAGE)


    def get_game_options(self, rom_info : RomInfo, additional_popup_options = [], rom_list= [], use_full_text = True):
        popup_options = []
        popup_options.extend(additional_popup_options)
        rom_name = os.path.basename(rom_info.rom_file_path)
        
        if(FavoritesManager.is_favorite(rom_info)):        
            popup_options.append(GridOrListEntry(
                primary_text="Remove Favorite" if use_full_text else "+/- Favorite",
                image_path=Theme.settings(),
                image_path_selected=Theme.settings_selected(),
                description=None,
                icon=None,
                value=lambda input_value, rom_info=rom_info: self.remove_favorite(rom_info, input_value)
            ))
        else:
            popup_options.append(GridOrListEntry(
                primary_text="Add Favorite" if use_full_text else "+/- Favorite",
                image_path=Theme.settings(),
                image_path_selected=Theme.settings_selected(),
                description=None,
                icon=None,
                value=lambda input_value, rom_info=rom_info: self.add_favorite(rom_info, input_value)
            ))
            
        
        popup_options.append(GridOrListEntry(
            primary_text="Add/Remove Collection" if use_full_text else "+/- Collection",
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description=None,
            icon=None,
            value=lambda input_value, rom_info=rom_info: self.collections_management_view(rom_info, input_value)
        ))

        popup_options.append(GridOrListEntry(
                primary_text="Launch Random Game",
                image_path=Theme.settings(),
                image_path_selected=Theme.settings_selected(),
                description=None,
                icon=None,
                value=lambda input_value, rom_list=rom_list: self.launch_random_game(input_value, rom_list)
        ))

        return popup_options


    def run_game_select_popup_menu(self, rom_info : RomInfo, additional_popup_options = [], rom_list= []):
        popup_options = []
        popup_options.append(GridOrListEntry(
            primary_text=f"{rom_info.game_system.display_name} Game Search",
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description=None,
            icon=None,
            value=lambda input_value, game_system=rom_info.game_system: self.execute_game_search(game_system, input_value)
        ))


        popup_options.extend(self.get_game_options(rom_info, additional_popup_options, rom_list, use_full_text=False)) 

        if(not Device.get_system_config().simple_mode_enabled()):
            popup_options.append(GridOrListEntry(
                primary_text=f"Toggle View",
                image_path=Theme.settings(),
                image_path_selected=Theme.settings_selected(),
                description=None,
                icon=None,
                value=lambda input_value: self.toggle_view()
            ))

        popup_view = ViewCreator.create_view(
            view_type=ViewType.POPUP,
            options=popup_options,
            top_bar_text=f"{rom_info.game_system.display_name} Menu Sub Options",
            selected_index=0,
            cols=Theme.popup_menu_cols(),
            rows=Theme.popup_menu_rows())


        while (popup_selection := popup_view.get_selection()):
            if(popup_selection.get_input() is not None):
                PyUiLogger.get_logger().info(f"Received {popup_selection.get_input()}")
                break
        
        if(popup_selection.get_input() is not None):
            popup_view.view_finished()

        if(ControllerInput.A == popup_selection.get_input()): 
            popup_selection.get_selection().get_value()(popup_selection.get_input())