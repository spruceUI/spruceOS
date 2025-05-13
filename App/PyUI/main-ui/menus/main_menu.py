
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from display.render_mode import RenderMode
from menus.app.app_menu import AppMenu
from menus.games.favorites_menu import FavoritesMenu
from menus.games.game_system_select_menu import GameSystemSelectMenu
from menus.main_menu_popup import MainMenuPopup
from menus.settings.basic_settings_menu import BasicSettingsMenu
from views.popup_text_list_view import PopupTextListView
from menus.games.recents_menu import RecentsMenu
from menus.settings.settings_menu import SettingsMenu
from themes.theme import Theme
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.grid_view import GridView
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class MainMenu:
    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme, config: PyUiConfig):
        self.display : Display= display
        self.controller : Controller = controller
        self.device : Device= device
        self.theme : Theme= theme
        self.system_select_menu = GameSystemSelectMenu(display,controller,device,theme)
        self.app_menu = AppMenu(display,controller,device,theme)
        self.favorites_menu = FavoritesMenu(display,controller,device,theme)
        self.recents_menu = RecentsMenu(display,controller,device,theme)
        self.settings_menu = BasicSettingsMenu(display,controller,device,theme, config)
        self.view_creator = ViewCreator(display,controller,device,theme)
        self.popup_menu = MainMenuPopup(display,controller,device,theme)

    def run_main_menu_selection(self):
        selected = Selection(None,None,0)
        expected_inputs = [ControllerInput.A, ControllerInput.MENU]
        while(selected.get_input() != ControllerInput.B):        
            #TODO make this user config driven
            first_entry = "Favorite"

            image_text_list = [
                GridOrListEntry(
                            primary_text=first_entry,
                            image_path=self.theme.favorite,
                            image_path_selected=self.theme.favorite_selected,
                            description=first_entry,
                            icon=self.theme.favorite,
                            value=first_entry
                ),                    
                GridOrListEntry(
                            primary_text="Game",
                            image_path=self.theme.game,
                            image_path_selected=self.theme.game_selected,
                            description="Your games",
                            icon=self.theme.game,
                            value="Game"
                ),
                GridOrListEntry(
                            primary_text="App",
                            image_path=self.theme.app,
                            image_path_selected=self.theme.app_selected,
                            description="Your Apps",
                            icon=self.theme.app,
                            value="App"
                ),      
                GridOrListEntry(
                            primary_text="Setting",
                            image_path=self.theme.settings,
                            image_path_selected=self.theme.settings_selected,
                            description="Your Apps",
                            icon=self.theme.settings,
                            value="Setting"
                ),            
            ]

            view = self.view_creator.create_view(
                view_type=self.theme.get_view_type_for_main_menu(),
                top_bar_text="SPRUCE", 
                options=image_text_list, 
                cols=4, 
                rows=1,
                selected_index=selected.get_index())
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
                        self.settings_menu.show_menu()
                elif(ControllerInput.MENU == selected.get_input()):
                    self.popup_menu.run_popup_menu_selection()