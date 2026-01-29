

import os
import random
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from display.on_screen_keyboard import OnScreenKeyboard
from games.utils.box_art_resizer import BoxArtResizer
from menus.games.collections.collections_management_menu import CollectionsManagementMenu
from menus.games.utils.custom_gameswitcher_list_manager import CustomGameSwitcherListManager
from menus.games.utils.favorites_manager import FavoritesManager
from menus.games.utils.rom_file_name_utils import RomFileNameUtils
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.rom_select_options_builder import get_rom_select_options_builder
from menus.settings.list_of_options_selection_menu import ListOfOptionsSelectionMenu
from themes.theme import Theme
from utils.boxart.box_art_scraper import BoxArtScraper
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType


from menus.language.language import Language

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
        Device.get_device().run_game(selected_rom.get_value())

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


    def download_boxart(self, input, rom_info : RomInfo):
        if (ControllerInput.A == input):
            rom_select_options_builder = get_rom_select_options_builder()

            rom_image_list = []
            img_path = rom_select_options_builder.get_default_image_path(rom_info.game_system, rom_info.rom_file_path)
            name_without_ext = RomFileNameUtils.get_rom_name_without_extensions(
                rom_info.game_system,
                rom_info.rom_file_path
            )
            rom_image_list.append((name_without_ext, img_path))
            
            BoxArtScraper().download_boxart_batch(rom_info.game_system.folder_name, rom_image_list)

    def find_index_for_boxart(self, boxart_name, boxart_list):
        name_lower = boxart_name.lower()

        best_index = 0
        best_prefix_len = 0

        for i, item in enumerate(boxart_list):
            item_lower = item.lower()

            prefix_len = 0
            for a, b in zip(name_lower, item_lower):
                if a != b:
                    break
                prefix_len += 1

            if prefix_len > best_prefix_len:
                best_prefix_len = prefix_len
                best_index = i

            #List isnt sorted case insenstively, if we change that
            #then we can early exit, not a big deal though

        return best_index

    def select_specific_boxart(self, input, rom_info : RomInfo):
        if (ControllerInput.A == input):
            Display.display_message("Loading boxart list...")
            scraper = BoxArtScraper()
            if(not scraper.check_wifi()):
                return

            image_list = scraper.get_image_list_for_system(rom_info.game_system.folder_name)
            if(image_list is not None):
                name_without_ext = RomFileNameUtils.get_rom_name_without_extensions(
                    rom_info.game_system,
                    rom_info.rom_file_path
                )

                start_index = self.find_index_for_boxart(name_without_ext, image_list)
                boxart_download = ListOfOptionsSelectionMenu().get_selected_option_index(image_list,"Select Box Art", start_index)

                if(boxart_download is not None):
                    box_art = image_list[boxart_download]
                    img_path = get_rom_select_options_builder().get_default_image_path(rom_info.game_system, rom_info.rom_file_path)
                    existing_image = get_rom_select_options_builder().get_image_path(rom_info)
                    if(existing_image is not None and os.path.exists(existing_image)):
                        os.remove(existing_image)
                        Display.clear_image_cache()
                    PyUiLogger().get_logger().info(f"Downloading {box_art} to {img_path}")
                    Display.display_message(f"Downloading {box_art} to {img_path}")
                    scraper.download_remote_image_for_system(rom_info.game_system.folder_name, box_art,img_path)
                    BoxArtResizer.patch_boxart_list([img_path])

    def get_game_options(self, rom_info : RomInfo, additional_popup_options = [], rom_list= [], use_full_text = True):
        popup_options = []
        popup_options.extend(additional_popup_options)
        rom_name = os.path.basename(rom_info.rom_file_path)
        
        if(PyUiConfig.get_gameswitcher_path() is not None 
           and Device.get_device().get_system_config().use_custom_gameswitcher_path()):
            if(CustomGameSwitcherListManager.contains_game(rom_info)):
                popup_options.append(GridOrListEntry(
                    primary_text=Language.remove_gameswitcher_game() if use_full_text else "+/- GameSwitcher",
                    image_path=Theme.settings(),
                    image_path_selected=Theme.settings_selected(),
                    description=None,
                    icon=None,
                    value=lambda input_value, rom_info=rom_info: CustomGameSwitcherListManager.remove_game(rom_info)
                ))
            else:
                popup_options.append(GridOrListEntry(
                    primary_text=Language.add_gameswitcher_game() if use_full_text else "+/- GameSwitcher",
                    image_path=Theme.settings(),
                    image_path_selected=Theme.settings_selected(),
                    description=None,
                    icon=None,
                    value=lambda input_value, rom_info=rom_info: CustomGameSwitcherListManager.add_game(rom_info)
                ))


        if(FavoritesManager.is_favorite(rom_info)):        
            popup_options.append(GridOrListEntry(
                primary_text=Language.remove_favorite() if use_full_text else "+/- Favorite",
                image_path=Theme.settings(),
                image_path_selected=Theme.settings_selected(),
                description=None,
                icon=None,
                value=lambda input_value, rom_info=rom_info: self.remove_favorite(rom_info, input_value)
            ))
        else:
            popup_options.append(GridOrListEntry(
                primary_text=Language.add_favorite() if use_full_text else "+/- Favorite",
                image_path=Theme.settings(),
                image_path_selected=Theme.settings_selected(),
                description=None,
                icon=None,
                value=lambda input_value, rom_info=rom_info: self.add_favorite(rom_info, input_value)
            ))
            
        
        popup_options.append(GridOrListEntry(
            primary_text=Language.add_remove_collection() if use_full_text else "+/- Collection",
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description=None,
            icon=None,
            value=lambda input_value, rom_info=rom_info: self.collections_management_view(rom_info, input_value)
        ))

               
        if(not Device.get_device().get_system_config().simple_mode_enabled()):               
            popup_options.append(GridOrListEntry(
                primary_text=Language.download_boxart(),
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=lambda input_value, rom_info=rom_info: self.download_boxart(input_value, rom_info)
            ))
            popup_options.append(GridOrListEntry(
                primary_text=Language.select_boxart(),
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=lambda input_value, rom_info=rom_info: self.select_specific_boxart(input_value, rom_info)
            ))

        popup_options.append(GridOrListEntry(
                primary_text=Language.launch_random_game(),
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

        if(not Device.get_device().get_system_config().simple_mode_enabled()):
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