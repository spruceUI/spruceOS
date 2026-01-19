

import os
from controller.controller_inputs import ControllerInput
from display.on_screen_keyboard import OnScreenKeyboard
from games.utils.game_system import GameSystem
from menus.app.app_menu import AppMenu
from menus.games.collections_menu import CollectionsMenu
from menus.games.favorites_menu import FavoritesMenu
from menus.games.recents_menu import RecentsMenu
from menus.games.search_games_for_system_menu import SearchGamesForSystemMenu
from menus.games.searched_roms_menu import SearchedRomsMenu
from menus.games.utils.rom_file_name_utils import RomFileNameUtils
from menus.games.utils.rom_select_options_builder import get_rom_select_options_builder
from menus.language.language import Language
from menus.settings.basic_settings_menu import BasicSettingsMenu
from themes.theme import Theme
from utils.boxart.box_art_scraper import BoxArtScraper
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType
from string import Template

class GameSystemSelectMenuPopup:
    def __init__(self):
        pass

    def execute_game_search(self, game_system, input_value):
        search_txt = OnScreenKeyboard().get_input(Language.game_search())
        if(search_txt is not None):
            return SearchGamesForSystemMenu(game_system, search_txt.upper()).run_rom_selection()
    
    def all_system_game_search(self, input_value):
        search_txt = OnScreenKeyboard().get_input(Language.game_search())
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

    def download_boxart(self, input, game_system : GameSystem):
        if (ControllerInput.A == input):
            rom_select_options_builder = get_rom_select_options_builder()

            roms = rom_select_options_builder.build_rom_list(game_system, subfolder=None)
            rom_image_list = []
            for rom in roms:
                if(rom.get_image_path() is not None and os.path.exists(rom.get_image_path())):
                    continue
                img_path = rom_select_options_builder.get_default_image_path(game_system, rom.get_value().rom_file_path)
                name_without_ext = RomFileNameUtils.get_rom_name_without_extensions(
                    rom.get_value().game_system,
                    rom.get_value().rom_file_path
                )
                rom_image_list.append((name_without_ext, img_path))
            
            BoxArtScraper().download_boxart_batch(game_system.folder_name, rom_image_list)

    def run_popup_menu_selection(self, game_system : GameSystem):
        popup_options = []

        if (Theme.skip_main_menu()):
            popup_options.append(
                GridOrListEntry(
                    primary_text=Language.recents(),
                    image_path=None,
                    image_path_selected=None,
                    description="",
                    icon=None,
                    value=self.open_recents
                )
            )
            popup_options.append(
                GridOrListEntry(
                    primary_text=Language.favorites(),
                    image_path=None,
                    image_path_selected=None,
                    description="",
                    icon=None,
                    value=self.open_favorites
                )
            )
            popup_options.append(
                GridOrListEntry(
                    primary_text=Language.collections(),
                    image_path=None,
                    image_path_selected=None,
                    description="",
                    icon=None,
                    value=self.open_collections
                )
            )
            popup_options.append(
                GridOrListEntry(
                    primary_text=Language.apps(),
                    image_path=None,
                    image_path_selected=None,
                    description="",
                    icon=None,
                    value=self.open_apps
                )
            )
            popup_options.append(
                GridOrListEntry(
                    primary_text=Language.settings(),
                    image_path=None,
                    image_path_selected=None,
                    description="",
                    icon=None,
                    value=self.open_settings
                )
            )


        popup_options.append(GridOrListEntry(
            primary_text=Template(Language.system_game_search()).substitute(system=game_system.display_name),
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description="",
            icon=Theme.settings(),
            value=lambda input_value, game_system=game_system: self.execute_game_search(game_system, input_value)
        ))
        popup_options.append(GridOrListEntry(
            primary_text=Language.all_system_game_search(),
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description="",
            icon=Theme.settings(),
            value=self.all_system_game_search
        ))
        popup_options.append(GridOrListEntry(
            primary_text=Language.download_boxart(),
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description="",
            icon=Theme.settings(),
            value=lambda input_value, game_system=game_system : self.download_boxart(input_value, game_system)
        ))

        

        popup_view = ViewCreator.create_view(
            view_type=ViewType.POPUP,
            options=popup_options,
            top_bar_text=Template(Language.system_menu_sub_options()).substitute(system=game_system.display_name),
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