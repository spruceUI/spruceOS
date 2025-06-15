

import os
from controller.controller_inputs import ControllerInput
from display.on_screen_keyboard import OnScreenKeyboard
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
    
    def execute_game_search(self, game_system, input_value):
        from menus.games.search_games_for_system_menu import SearchGamesForSystemMenu
        search_txt = OnScreenKeyboard().get_input("Game Search:")
        if(search_txt is not None):
            SearchGamesForSystemMenu(game_system, search_txt.upper()).run_rom_selection()

    def toggle_view(self):
        if(ViewType.TEXT_AND_IMAGE == Theme.get_game_selection_view_type()):
            Theme.set_game_selection_view_type(ViewType.GRID)
        elif(ViewType.GRID == Theme.get_game_selection_view_type()):
            Theme.set_game_selection_view_type(ViewType.CAROUSEL)
        else:
            Theme.set_game_selection_view_type(ViewType.TEXT_AND_IMAGE)


    def run_game_select_popup_menu(self, rom_info : RomInfo):
        popup_options = []
        rom_name = os.path.basename(rom_info.rom_file_path)
        
        if(FavoritesManager.is_favorite(rom_info)):        
            popup_options.append(GridOrListEntry(
                primary_text="Remove Favorite",
                image_path=Theme.settings(),
                image_path_selected=Theme.settings_selected(),
                description=f"Remove {rom_name} as a favorite",
                icon=Theme.settings(),
                value=lambda input_value, rom_info=rom_info: self.remove_favorite(rom_info, input_value)
            ))
        else:
            popup_options.append(GridOrListEntry(
                primary_text="Add Favorite",
                image_path=Theme.settings(),
                image_path_selected=Theme.settings_selected(),
                description=f"Add {rom_name} as a favorite",
                icon=Theme.settings(),
                value=lambda input_value, rom_info=rom_info: self.add_favorite(rom_info, input_value)
            ))
            
        popup_options.append(GridOrListEntry(
            primary_text=f"{rom_info.game_system.display_name} Game Search",
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description="",
            icon=Theme.settings(),
            value=lambda input_value, game_system=rom_info.game_system: self.execute_game_search(game_system, input_value)
        ))
            
        popup_options.append(GridOrListEntry(
            primary_text=f"Toggle View",
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description="",
            icon=Theme.settings(),
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
            PyUiLogger.get_logger().info(f"Waiting for input")
            if(popup_selection.get_input() is not None):
                PyUiLogger.get_logger().info(f"Received {popup_selection.get_input()}")
                break
        
        if(popup_selection.get_input() is not None):
            popup_view.view_finished()

        if(ControllerInput.A == popup_selection.get_input()): 
            popup_selection.get_selection().get_value()(popup_selection.get_input())