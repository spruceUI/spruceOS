
import os
import subprocess
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from menus.games.game_config_menu import GameConfigMenu
from menus.games.game_select_menu_popup import GameSelectMenuPopup
from menus.games.in_game_menu_listener import InGameMenuListener
from menus.games.utils.collections_manager import CollectionsManager
from menus.games.utils.recents_manager import RecentsManager
from menus.games.utils.rom_file_name_utils import RomFileNameUtils
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.rom_select_options_builder import get_rom_select_options_builder
from themes.theme import Theme
from utils.logger import PyUiLogger
from utils.py_ui_state import PyUiState
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from abc import ABC, abstractmethod

from views.view_creator import ViewCreator
from views.view_type import ViewType


class RomsMenuCommon(ABC):
    def __init__(self, ):
        self.in_game_menu_listener = InGameMenuListener()
        self.popup_menu = GameSelectMenuPopup()
        
        self.support_only_game_launching = Device.get_device().get_system_config().game_selection_only_mode_enabled()

    def _remove_extension(self,file_name):
        return os.path.splitext(file_name)[0]
    
    def _get_image_path(self, rom_path):
        # Get the base filename without extension (e.g., "DKC")
        return get_rom_select_options_builder().get_image_path(rom_path, prefer_savestate_screenshot=self.prefer_savestate_screenshot())
        
    def _extract_game_system(self, rom_path):
        rom_path = os.path.abspath(os.path.normpath(rom_path))
        parts = os.path.normpath(rom_path).split(os.sep)
        try:
            roms_index = [p.lower() for p in parts].index("roms")
            return parts[roms_index + 1]
        except (ValueError, IndexError) as e:
            PyUiLogger.get_logger().error(f"Error extracting subdirectory after 'Roms' for {rom_path}: {e}")
        return None  # "Roms" not found or no subdirectory after it
    
    @abstractmethod
    def _get_rom_list(self) -> list[GridOrListEntry]:
        pass
    
    def _run_subfolder_menu(self, rom_info : RomInfo) -> list[GridOrListEntry]:
        from menus.games.game_select_menu import GameSelectMenu
        return GameSelectMenu().run_rom_selection(rom_info.game_system, rom_info.rom_file_path)


    def _load_collection_menu(self, rom_info : RomInfo) -> list[GridOrListEntry]:
        self.current_collection = rom_info.rom_file_path
        PyUiState.set_in_game_selection_screen(True)
        rom_list = self.build_rom_selection_for_collection(self.current_collection)
        while(ControllerInput.B != self._run_rom_selection_for_rom_list(self.current_collection, rom_list)):
            pass

        PyUiState.set_in_game_selection_screen(False)
        self.current_collection = None

    def build_rom_selection_for_collection(self, collection):
        raw_rom_list = CollectionsManager.get_games_in_collection(collection)
        
        rom_list = []

        for rom_info in raw_rom_list:
            rom_file_name = RomFileNameUtils.get_rom_name_without_extensions(rom_info.game_system, rom_info.rom_file_path)
            img_path = self._get_image_path(rom_info)
            rom_list.append(
                GridOrListEntry(
                    primary_text=self._remove_extension(rom_file_name)  +" (" + self._extract_game_system(rom_info.rom_file_path)+")",
                    image_path=img_path,
                    image_path_selected=img_path,
                    description=collection, 
                    icon=None,
                    value=rom_info)
            )
        return rom_list

    def get_view_type(self):
        return Theme.get_game_selection_view_type()

    def full_screen_grid_resize_type(self):
        return Theme.get_full_screen_grid_game_menu_resize_type()

    def get_set_top_bar_text_to_game_selection(self):
        return Theme.get_set_top_bar_text_to_game_selection()

    def get_game_select_row_count(self):
        return Theme.get_game_select_row_count()
    
    def get_game_select_col_count(self):
        return Theme.get_game_select_col_count()
    
    def get_game_select_carousel_col_count(self):
        return Theme.get_game_select_carousel_col_count()
    
    def get_image_resize_height_multiplier(self):
        return None
    
    def create_view(self, page_name, rom_list, selected):
        return ViewCreator.create_view(
                        view_type=self.get_view_type(),
                        top_bar_text=page_name,
                        options=rom_list,
                        selected_index=selected.get_index(),
                        rows=self.get_game_select_row_count(),
                        cols=self.get_game_select_col_count(),
                        carousel_cols=Theme.get_game_select_carousel_col_count(),
                        grid_resized_width=Theme.get_grid_game_select_img_width(),
                        grid_resized_height=Theme.get_grid_game_select_img_height(),
                        use_mutli_row_grid_select_as_backup_for_single_row_grid_select=Theme.get_game_select_show_sel_bg_grid_mode(),
                        hide_grid_bg=not Theme.get_game_select_show_sel_bg_grid_mode(),
                        show_grid_text=Theme.get_game_select_show_text_grid_mode(),
                        set_top_bar_text_to_selection=self.get_set_top_bar_text_to_game_selection(), 
                        set_bottom_bar_text_to_selection=not Theme.get_set_top_bar_text_to_game_selection() and (Theme.get_game_selection_view_type() == ViewType.CAROUSEL or Theme.get_game_selection_view_type() == ViewType.GRID),
                        grid_selected_bg=Theme.get_grid_game_selected_bg(),
                        grid_resize_type=Theme.get_grid_game_selected_resize_type(),
                        grid_img_y_offset=Theme.get_grid_game_img_y_offset(),
                        carousel_selected_entry_width_percent=Theme.get_carousel_game_select_primary_img_width(),
                        carousel_shrink_further_away=Theme.get_carousel_game_select_shrink_further_away(),
                        carousel_sides_hang_off_edge=Theme.get_carousel_game_select_sides_hang_off(),
                        missing_image_path=Theme.get_missing_image_path(),
                        allow_scrolling_text=True, # roms select is allowed to scroll
                        full_screen_grid_resize_type=self.full_screen_grid_resize_type(),
                        image_resize_height_multiplier=self.get_image_resize_height_multiplier())

    def _run_rom_selection(self, page_name) :
        rom_list = self._get_rom_list()
        return self._run_rom_selection_for_rom_list(page_name,rom_list)

    def get_additional_menu_options(self):
        return []

    def _menu_pressed(self, selection, rom_list):
        self.popup_menu.run_game_select_popup_menu(selection, self.get_additional_menu_options(), rom_list)

    def _get_menu_button_game_options(self, selection, rom_list):
        return self.popup_menu.get_game_options(selection, self.get_additional_menu_options(), rom_list, use_full_text=True)

    def _check_for_last_subfolder_existance(self, last_subfolder, rom_list):
        if (
            last_subfolder != '' and
            getattr(self, 'subfolder', '') != last_subfolder and
            getattr(self, 'subfolder', '') != '' and
            os.path.isdir(last_subfolder)
        ):
            PyUiLogger.get_logger().info(f"Subfolder does not match {last_subfolder} vs {getattr(self, 'subfolder', '') }")
            rom_info_subfolder = RomInfo(game_system=rom_list[0].get_value().game_system,rom_file_path=last_subfolder)
            return_value = self._run_subfolder_menu(rom_info_subfolder)
            if(return_value is not None and return_value != ControllerInput.B):
                return return_value

    def default_to_last_game_selection(self):
        return True
   
    def _run_rom_selection_for_rom_list(self, page_name, rom_list) :
        selected = Selection(None,None,0)
        view = None
        last_game_file_path, last_subfolder = PyUiState.get_last_game_selection(page_name)

        last_subfolder = self._check_for_last_subfolder_existance(last_subfolder, rom_list)

        if(last_subfolder is not None):
            return last_subfolder

        if(self.default_to_last_game_selection()):
            for index, entry in enumerate(rom_list):
                if(entry.get_value().rom_file_path == last_game_file_path):
                    selected = Selection(None,None,index)

        while(selected is not None):
            Display.set_page_bg(page_name)
            if(view is None):
                view = self.create_view(page_name,rom_list,selected)
            else:
                view.set_options(rom_list)

            accepted_inputs = [ControllerInput.A, ControllerInput.X, ControllerInput.MENU, ControllerInput.SELECT]
            if(Theme.skip_main_menu()):
                accepted_inputs += [ControllerInput.L1, ControllerInput.R1]
            selected = view.get_selection(accepted_inputs)
            if(selected is not None and (selected.get_selection() is not None or ControllerInput.B == selected.get_input())):
                if(ControllerInput.A == selected.get_input()):
                    PyUiState.set_last_game_selection(
                        page_name,
                        selected.get_selection().get_value().rom_file_path,
                        getattr(self, 'subfolder', '') or ''
                    )

                    if(selected.get_selection().get_value().is_collection):
                        PyUiState.set_last_game_selection(
                            page_name,
                            "Collection",
                            selected.get_selection().get_value().rom_file_path
                        )
                        
                        self._load_collection_menu(selected.get_selection().get_value())
                        
                        PyUiState.set_last_game_selection(
                            page_name,
                            selected.get_selection().get_value().rom_file_path,
                            getattr(self, 'subfolder', '') or ''
                        )
                            
                    elif(self.launched_via_special_case(selected.get_selection().get_value())):
                        pass
                    
                    elif(os.path.isdir(selected.get_selection().get_value().rom_file_path)):
                        # If the selected item is a directory, open it
                        PyUiState.set_last_game_selection(
                            page_name,
                            "",
                            selected.get_selection().get_value().rom_file_path
                        )
                        return_value = self._run_subfolder_menu(selected.get_selection().get_value())
                        if(return_value is not None and return_value != ControllerInput.B):
                            return return_value
                        else:
                            PyUiState.set_last_game_selection(
                            page_name,
                            selected.get_selection().get_value().rom_file_path,
                            getattr(self, 'subfolder', '') or ''
                        )

                    else:
                        RecentsManager.add_game(selected.get_selection().get_value())
                        self.run_game(selected.get_selection().get_value())
                elif(ControllerInput.X == selected.get_input() and not self.support_only_game_launching):
                    gen_additional_game_options = lambda selected=selected.get_selection().get_value(), rom_list=rom_list, self=self: self._get_menu_button_game_options(selected, rom_list)
                    GameConfigMenu(
                        selected.get_selection().get_value().game_system, 
                        selected.get_selection().get_value(), 
                        gen_additional_game_options
                    ).show_config(os.path.basename(selected.get_selection().get_value().rom_file_path))
                    # Regenerate as game config menu might've changed something
                    rom_list = self._get_rom_list()
                elif(ControllerInput.MENU == selected.get_input() and not self.support_only_game_launching):
                    prev_view = Theme.get_game_selection_view_type()
                    self._menu_pressed(selected.get_selection().get_value(), rom_list)
                    # Regenerate as game config menu might've changed something
                    original_length = len(rom_list)
                    rom_list = self._get_rom_list()
                    new_length = len(rom_list)
                    if(Theme.get_game_selection_view_type() != prev_view or original_length != new_length):
                        view = self.create_view(page_name,rom_list,selected)
                elif(ControllerInput.B == selected.get_input() and (not self.support_only_game_launching)):
                    
                    #What is happening on muOS where this is becoming None?
                    if(selected is not None and selected.get_selection() is not None and selected.get_selection().get_value() is not None):
                        PyUiState.set_last_game_selection(
                            page_name,
                            selected.get_selection().get_value().rom_file_path,
                            getattr(self, 'subfolder', '') or ''
                        )

                        if(selected.get_selection().get_value().is_collection):
                            PyUiState.set_last_game_selection(
                                page_name,
                                "Collection",
                                selected.get_selection().get_value().rom_file_path
                            )
                        
                    return ControllerInput.B
                elif(ControllerInput.SELECT == selected.get_input() and not self.support_only_game_launching):
                    if(ViewType.TEXT_AND_IMAGE == Theme.get_game_selection_view_type()):
                        Theme.set_game_selection_view_type(ViewType.GRID)
                        view = self.create_view(page_name,rom_list,selected)
                    elif(ViewType.GRID == Theme.get_game_selection_view_type()):
                        Theme.set_game_selection_view_type(ViewType.CAROUSEL)
                        view = self.create_view(page_name,rom_list,selected)
                    elif(ViewType.CAROUSEL == Theme.get_game_selection_view_type()):
                        Theme.set_game_selection_view_type(ViewType.FULLSCREEN_GRID)
                        view = self.create_view(page_name,rom_list,selected)
                    elif(ViewType.FULLSCREEN_GRID == Theme.get_game_selection_view_type()):
                        Theme.set_game_selection_view_type(ViewType.TEXT_AND_IMAGE)
                        view = self.create_view(page_name,rom_list,selected)
                    else: # how did we hit this else?
                        Theme.set_game_selection_view_type(ViewType.TEXT_AND_IMAGE)
                        view = self.create_view(page_name,rom_list,selected)
                elif(Theme.skip_main_menu() and ControllerInput.L1 == selected.get_input()):
                    PyUiState.set_last_game_selection(
                        page_name,
                        selected.get_selection().get_value().rom_file_path,
                        getattr(self, 'subfolder', '') or ''
                    )
                    return ControllerInput.L1
                elif(Theme.skip_main_menu() and ControllerInput.R1 == selected.get_input()):
                    PyUiState.set_last_game_selection(
                        page_name,
                        selected.get_selection().get_value().rom_file_path,
                        getattr(self, 'subfolder', '') or ''
                    )
                    return ControllerInput.R1

        Display.restore_bg()
        
    def run_game(self, game_path):
        PyUiLogger.get_logger().info("run_game(" + game_path.rom_file_path +")")
        #recents is handled one level up to account for launched_via_special_case
        Display.deinit_display()

        game_thread: subprocess.Popen = Device.get_device().run_game(game_path)
        if (game_thread is not None):
            self.in_game_menu_listener.game_launched(
                game_thread, game_path)
            Controller.clear_input_queue()

        Display.reinitialize()
        PyUiLogger.get_logger().info("Finished run_game(" + game_path.rom_file_path +")")


    def launched_via_special_case(self, rom_info : RomInfo):
        subfolder_launch_file = rom_info.game_system.game_system_config.subfolder_launch_file()

        if(subfolder_launch_file is not None and subfolder_launch_file != ""):
            RecentsManager.add_game(rom_info)
            folder = rom_info.rom_file_path
            launch_file = os.path.join(folder,subfolder_launch_file)
            if(os.path.isfile(launch_file)):
                self.run_game(RomInfo(rom_info.game_system,launch_file))
                return True
        else:
            return False