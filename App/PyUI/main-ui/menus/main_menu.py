
from controller.controller_inputs import ControllerInput
from menus.app.app_menu import AppMenu
from menus.games.favorites_menu import FavoritesMenu
from menus.games.game_system_select_menu import GameSystemSelectMenu
from menus.main_menu_popup import MainMenuPopup
from menus.settings.basic_settings_menu import BasicSettingsMenu
from menus.games.recents_menu import RecentsMenu
from themes.theme import Theme
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator


class MainMenu:
    def __init__(self):
        self.system_select_menu = GameSystemSelectMenu()
        self.app_menu = AppMenu()
        self.favorites_menu = FavoritesMenu()
        self.recents_menu = RecentsMenu()
        self.settings_menu = BasicSettingsMenu()
        self.popup_menu = MainMenuPopup()

    def build_options(self):
        #TODO make this user config driven
        #first_entry = "Favorite"
        show_favorite = True
        show_recents = True
            
        image_text_list = []
        if(show_recents):
            image_text_list.append(
                GridOrListEntry(
                    primary_text="Recent",
                    image_path=Theme.recent(),
                    image_path_selected=Theme.recent_selected(),
                    description="Recent",
                    icon=None,
                    value="Recent"
                )
            )

        if(show_favorite):
             image_text_list.append(
                GridOrListEntry(
                    primary_text="Favorite",
                    image_path=Theme.favorite(),
                    image_path_selected=Theme.favorite_selected(),
                    description="Favorite",
                    icon=None,
                    value="Favorite"
                )
            )
             
        image_text_list.append(
            GridOrListEntry(
                primary_text="Game",
                image_path=Theme.game(),
                image_path_selected=Theme.game_selected(),
                description="Your games",
                icon=None,
                value="Game"
            )
        )
        image_text_list.append(
             GridOrListEntry(
                 primary_text="App",
                image_path=Theme.app(),
                image_path_selected=Theme.app_selected(),
                description="Your Apps",
                icon=None,
                value="App"
            )
        )
        image_text_list.append(
             GridOrListEntry(
                primary_text="Setting",
                image_path=Theme.settings(),
                image_path_selected=Theme.settings_selected(),
                description="Your Apps",
                icon=None,
                value="Setting"
            )
        )
        return image_text_list

    def build_main_menu_view(self, options, selected):
        return ViewCreator.create_view(
            view_type=Theme.get_view_type_for_main_menu(),
            top_bar_text="PyUI", 
            options=options, 
            cols=Theme.get_main_menu_column_count(), 
            rows=1,
            selected_index=selected.get_index())

    def run_main_menu_selection(self):
        selected = Selection(None,None,0)

        image_text_list = self.build_options()
        view =  self.build_main_menu_view(image_text_list, selected)        
            
        expected_inputs = [ControllerInput.A, ControllerInput.MENU]
        while(selected.get_input() != ControllerInput.B):      
            view.set_options(self.build_options())  

            if((selected := view.get_selection(expected_inputs)) is not None):       
                if(ControllerInput.A == selected.get_input()): 
                    if("Game" == selected.get_selection().get_primary_text()):
                        self.system_select_menu.run_system_selection()
                    elif("App" == selected.get_selection().get_primary_text()):
                        self.app_menu.run_app_selection()
                    elif("Favorite" == selected.get_selection().get_primary_text()):
                        self.favorites_menu.run_rom_selection()
                    elif("Recent" == selected.get_selection().get_primary_text()):
                        self.recents_menu.run_rom_selection()
                    elif("Setting" == selected.get_selection().get_primary_text()):
                        theme_updated = self.settings_menu.show_menu()
                        if(theme_updated):
                            view =  self.build_main_menu_view(image_text_list, selected)        

                elif(ControllerInput.MENU == selected.get_input()):
                    self.popup_menu.run_popup_menu_selection()