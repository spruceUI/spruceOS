
from controller.controller_inputs import ControllerInput
from display.display import Display
from menus.app.app_menu import AppMenu
from menus.games.collections_menu import CollectionsMenu
from menus.games.favorites_menu import FavoritesMenu
from menus.games.game_system_select_menu import GameSystemSelectMenu
from menus.language.language import Language
from menus.main_menu_popup import MainMenuPopup
from menus.settings.basic_settings_menu import BasicSettingsMenu
from menus.games.recents_menu import RecentsMenu
from themes.theme import Theme
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from utils.py_ui_state import PyUiState
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator


class MainMenu:
    def __init__(self):
        self.system_select_menu = GameSystemSelectMenu()
        self.app_menu = AppMenu()
        self.favorites_menu = FavoritesMenu()
        self.collections_menu = CollectionsMenu()
        self.recents_menu = RecentsMenu()
        self.settings_menu = BasicSettingsMenu()
        self.popup_menu = MainMenuPopup()

    def reorder_options(self,ordering, objects):
        # Create a lookup map for ordering priority
        order_map = {text: index for index, text in enumerate(ordering)}
        
        # Sort objects based on the index of their primary text in the ordering list
        return sorted(objects, key=lambda obj: order_map.get(obj.get_primary_text(), float('inf')))

    def build_options(self):
        image_text_list = []
        if (Theme.get_recents_enabled()):
            image_text_list.append(
                GridOrListEntry(
                    primary_text=Language.recents(),
                    image_path=Theme.recent(),
                    image_path_selected=Theme.recent_selected(),
                    description="Recent",
                    icon=None,
                    value="Recent"
                )
            )

        if (Theme.get_collections_enabled()):
            image_text_list.append(
                GridOrListEntry(
                    primary_text=Language.collections(),
                    image_path=Theme.collection(),
                    image_path_selected=Theme.collection_selected(),
                    description="Collection",
                    icon=None,
                    value="Collection"
                )
            )

        if (Theme.get_favorites_enabled()):
            image_text_list.append(
                GridOrListEntry(
                    primary_text=Language.favorites(),
                    image_path=Theme.favorite(),
                    image_path_selected=Theme.favorite_selected(),
                    description="Favorite",
                    icon=None,
                    value="Favorite"
                )
            )

        image_text_list.append(
            GridOrListEntry(
                primary_text=Language.games(),
                image_path=Theme.game(),
                image_path_selected=Theme.game_selected(),
                description="Your games",
                icon=None,
                value="Game"
            )
        )

        if (Theme.get_apps_enabled()):

            image_text_list.append(
                GridOrListEntry(
                    primary_text=Language.apps(),
                    image_path=Theme.app(),
                    image_path_selected=Theme.app_selected(),
                    description="Your Apps",
                    icon=None,
                    value="App"
                )
            )

        if (Theme.get_settings_enabled()):
            image_text_list.append(
                GridOrListEntry(
                    primary_text=Language.settings(),
                    image_path=Theme.settings(),
                    image_path_selected=Theme.settings_selected(),
                    description="Your Apps",
                    icon=None,
                    value="Setting"
                )
            )

            
        return self.reorder_options(Theme.get_main_menu_option_ordering(),image_text_list)

    def build_main_menu_view(self, options, selected):
        return ViewCreator.create_view(
            view_type=Theme.get_view_type_for_main_menu(),
            top_bar_text=PyUiConfig.get_main_menu_title(), 
            options=options, 
            cols=Theme.get_main_menu_column_count(), 
            rows=1,
            selected_index=selected.get_index(),
            show_grid_text=Theme.get_main_menu_show_text_grid_mode())

    def launch_selection(self, selection):
        if("Game" == selection):
            PyUiLogger.get_logger().info(f"Launching Game Menu")
            PyUiState.set_last_main_menu_selection("Game")
            self.system_select_menu.run_system_selection()
            PyUiState.set_last_main_menu_selection(None)
        elif("App" == selection):
            PyUiLogger.get_logger().info(f"Launching App Menu")
            PyUiState.set_last_main_menu_selection("App")
            self.app_menu.run_app_selection()
            PyUiState.set_last_main_menu_selection(None)
        elif("Favorite" == selection):
            PyUiLogger.get_logger().info(f"Launching Favorite Menu")
            PyUiState.set_last_main_menu_selection("Favorite")
            self.favorites_menu.run_rom_selection()
            PyUiState.set_last_main_menu_selection(None)
        elif("Collection" == selection):
            PyUiLogger.get_logger().info(f"Launching Collection Menu")
            PyUiState.set_last_main_menu_selection("Collection")
            self.collections_menu.run_rom_selection()
            PyUiState.set_last_main_menu_selection(None)
        elif("Recent" == selection):
            PyUiLogger.get_logger().info(f"Launching Recent Menu")
            PyUiState.set_last_main_menu_selection("Recent")
            self.recents_menu.run_rom_selection()
            PyUiState.set_last_main_menu_selection(None)
        elif("Setting" == selection):
            PyUiLogger.get_logger().info(f"Launching Setting Menu")
            # Don't save state for settings
            self.settings_menu.show_menu()


    def run_main_menu_selection(self):
        self.launch_selection(PyUiState.get_last_main_menu_selection())            

        if(Theme.skip_main_menu()):
            selection = "Games"
            while(True):
                Display.set_selected_tab(selection)
                if("Games" == selection):
                    PyUiState.set_last_main_menu_selection("Game")
                    controller_input = self.system_select_menu.run_system_selection()
                    if(ControllerInput.L1 == controller_input):
                        selection = "Settings"
                    elif(ControllerInput.R1 == controller_input):
                        selection = "Apps"
                    PyUiState.set_last_main_menu_selection(None)
                elif("Apps" == selection):
                    PyUiState.set_last_main_menu_selection("App")
                    controller_input = self.app_menu.run_app_selection()
                    if(ControllerInput.L1 == controller_input):
                        selection = "Games"
                    elif(ControllerInput.R1 == controller_input):
                        selection = "Settings"
                    PyUiState.set_last_main_menu_selection(None)
                elif("Settings" == selection):
                    controller_input = self.settings_menu.show_menu()
                    if(ControllerInput.L1 == controller_input):
                        selection = "Apps"
                    elif(ControllerInput.R1 == controller_input):
                        selection = "Games"
                    PyUiState.set_last_main_menu_selection(None)

        else:
            selected = Selection(None,None,0)

            image_text_list = self.build_options()
            view =  self.build_main_menu_view(image_text_list, selected)        
                
            expected_inputs = [ControllerInput.A, ControllerInput.MENU]
            while(True):      

                if((selected := view.get_selection(expected_inputs)) is not None):       
                    if(ControllerInput.A == selected.get_input()): 
                        self.launch_selection(selected.get_selection().get_value())
                    elif(ControllerInput.MENU == selected.get_input()):
                        self.popup_menu.run_popup_menu_selection()

                    if(selected.get_input() is not None):
                        image_text_list = self.build_options()
                        view =  self.build_main_menu_view(image_text_list, selected)        
