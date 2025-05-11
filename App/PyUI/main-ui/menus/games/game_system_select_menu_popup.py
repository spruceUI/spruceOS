

from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from games.utils.game_system import GameSystem
from menus.games.search_games_for_system_menu import SearchGamesForSystemMenu
from menus.games.searched_roms_menu import SearchedRomsMenu
from themes.theme import Theme
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType


class GameSystemSelectMenuPopup:
    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme):
        self.display : Display= display
        self.controller : Controller = controller
        self.device : Device= device
        self.theme : Theme= theme
        self.view_creator = ViewCreator(display,controller,device,theme)

    def execute_game_search(self, game_system, input_value):
        SearchGamesForSystemMenu(self.display,self.controller,self.device,self.theme, game_system).run_rom_selection()


    def run_popup_menu_selection(self, game_system : GameSystem):
        popup_options = []
        popup_options.append(GridOrListEntry(
            primary_text=f"{game_system.display_name} Game Search",
            image_path=self.theme.settings,
            image_path_selected=self.theme.settings_selected,
            description="",
            icon=self.theme.settings,
            value=lambda input_value, game_system=game_system: self.execute_game_search(game_system, input_value)
        ))

        popup_view = self.view_creator.create_view(
            view_type=ViewType.POPUP_TEXT_LIST_VIEW,
            options=popup_options,
            top_bar_text=f"{game_system} Menu Sub Options",
            selected_index=0,
            cols=self.theme.popup_menu_cols,
            rows=self.theme.popup_menu_rows)
                        

        while (popup_selection := popup_view.get_selection()):
            print(f"Waiting for input")
            if(popup_selection.get_input() is not None):
                print(f"Received {popup_selection.get_input()}")
                break
        
        if(popup_selection.get_input() is not None):
            popup_view.view_finished()

        if(ControllerInput.A == popup_selection.get_input()): 
            popup_selection.get_selection().get_value()(popup_selection.get_input())