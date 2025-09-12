

from controller.controller_inputs import ControllerInput
from display.on_screen_keyboard import OnScreenKeyboard
from games.utils.game_system import GameSystem
from menus.app.app_menu import AppMenu
from menus.games.collections_menu import CollectionsMenu
from menus.games.favorites_menu import FavoritesMenu
from menus.games.recents_menu import RecentsMenu
from menus.games.search_games_for_system_menu import SearchGamesForSystemMenu
from menus.games.searched_roms_menu import SearchedRomsMenu
from menus.settings.basic_settings_menu import BasicSettingsMenu
from themes.theme import Theme
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType


class GameSystemSelectMenuPopup:
    def __init__(self):
        pass

    def execute_game_search(self, game_system, input_value):
        search_txt = OnScreenKeyboard().get_input("Game Search:")
        if(search_txt is not None):
            return SearchGamesForSystemMenu(game_system, search_txt.upper()).run_rom_selection()
    
    def all_system_game_search(self, input_value):
        search_txt = OnScreenKeyboard().get_input("Game Search:")
        if(search_txt is not None):
            return SearchedRomsMenu(search_txt.upper()).run_rom_selection()

    def open_settings(self, input):
        if (ControllerInput.A == input):
            BasicSettingsMenu().show_menu()

    def open_apps(self, input):
        if (ControllerInput.A == input):
            AppMenu().run_app_selection()

    def open_recents(self, input):
        if (ControllerInput.A == input):
            RecentsMenu().run_rom_selection()

    def open_favorites(self, input):
        if (ControllerInput.A == input):
            FavoritesMenu().run_rom_selection()

    def open_collections(self, input):
        if (ControllerInput.A == input):
            CollectionsMenu().run_rom_selection()

    def run_popup_menu_selection(self, game_system : GameSystem):
        popup_options = []

        if (Theme.skip_main_menu()):
            popup_options.append(
                GridOrListEntry(
                    primary_text="Recents",
                    image_path=None,
                    image_path_selected=None,
                    description="",
                    icon=None,
                    value=self.open_recents
                )
            )
            popup_options.append(
                GridOrListEntry(
                    primary_text="Favorites",
                    image_path=None,
                    image_path_selected=None,
                    description="",
                    icon=None,
                    value=self.open_favorites
                )
            )
            popup_options.append(
                GridOrListEntry(
                    primary_text="Collections",
                    image_path=None,
                    image_path_selected=None,
                    description="",
                    icon=None,
                    value=self.open_collections
                )
            )

        if (Theme.skip_main_menu()):
            popup_options.append(
                GridOrListEntry(
                    primary_text="Apps",
                    image_path=None,
                    image_path_selected=None,
                    description="",
                    icon=None,
                    value=self.open_apps
                )
            )
            popup_options.append(
                GridOrListEntry(
                    primary_text="Settings",
                    image_path=None,
                    image_path_selected=None,
                    description="",
                    icon=None,
                    value=self.open_settings
                )
            )


        popup_options.append(GridOrListEntry(
            primary_text=f"{game_system.display_name} Game Search",
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description="",
            icon=Theme.settings(),
            value=lambda input_value, game_system=game_system: self.execute_game_search(game_system, input_value)
        ))
        popup_options.append(GridOrListEntry(
            primary_text="All System Game Search",
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description="",
            icon=Theme.settings(),
            value=self.all_system_game_search
        ))

        popup_view = ViewCreator.create_view(
            view_type=ViewType.POPUP,
            options=popup_options,
            top_bar_text=f"{game_system} Menu Sub Options",
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