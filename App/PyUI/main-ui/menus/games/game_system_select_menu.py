
import os
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from games.utils.game_system_utils import GameSystemUtils
from menus.games.game_select_menu import GameSelectMenu
from menus.games.game_system_config import GameSystemConfig
from menus.games.game_system_select_menu_popup import GameSystemSelectMenuPopup
from themes.theme import Theme
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.grid_view import GridView
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class GameSystemSelectMenu:
    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme):
        self.display : Display= display
        self.controller : Controller = controller
        self.device : Device= device
        self.theme : Theme= theme
        self.game_utils : GameSystemUtils = GameSystemUtils()
        self.rom_select_menu : GameSelectMenu = GameSelectMenu(display,controller,device,theme)
        self.use_emu_cfg = False
        self.view_creator = ViewCreator(display,controller,device,theme)
        self.game_system_select_menu_popup = GameSystemSelectMenuPopup(display,controller,device,theme)

    def get_system_name_for_icon(self, sys_config):        
        return os.path.splitext(os.path.basename(sys_config.get_icon()))[0]

    def run_system_selection(self) :
        selected = Selection(None,None,0)
        systems_list = []
        view = None
        for game_system in self.game_utils.get_active_systems():
            sys_config = game_system.game_system_config
            if(self.use_emu_cfg):
                systems_list.append(
                    GridOrListEntry(
                        primary_text=game_system.display_name,
                        image_path=sys_config.get_icon(),
                        image_path_selected=sys_config.get_icon_selected(),
                        description="Game System",
                        icon=sys_config.get_icon_selected(),
                        value=game_system
                    ) 
                )
            else:
                icon_system_name = self.get_system_name_for_icon(sys_config)
                systems_list.append(
                    GridOrListEntry(
                        primary_text=game_system.display_name,
                        image_path=self.theme.get_system_icon(icon_system_name),
                        image_path_selected=self.theme.get_system_icon_selected(icon_system_name),
                        description="Game System",
                        icon=self.theme.get_system_icon_selected(game_system.folder_name),
                        value=game_system
                    )                
                )
        if(view is None):
            view = self.view_creator.create_view(
                view_type=self.theme.get_view_type_for_system_select_menu(),
                top_bar_text="Game", 
                options=systems_list, 
                cols=self.theme.get_game_system_select_col_count(), 
                rows=self.theme.get_game_system_select_row_count(),
                selected_index=selected.get_index())
        else:
            view.set_options(systems_list)

        exit = False
        while(not exit):
            selected = view.get_selection([ControllerInput.A, ControllerInput.MENU])
            if(ControllerInput.A == selected.get_input()):
                self.rom_select_menu.run_rom_selection(selected.get_selection().get_value())
            elif(ControllerInput.MENU == selected.get_input()):
                self.game_system_select_menu_popup.run_popup_menu_selection(selected.get_selection().get_value())
            elif(ControllerInput.B == selected.get_input()):
                exit = True