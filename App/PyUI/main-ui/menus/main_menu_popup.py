

from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from display.on_screen_keyboard import OnScreenKeyboard
from menus.games.searched_roms_menu import SearchedRomsMenu
from themes.theme import Theme
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType


class MainMenuPopup:
    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme):
        self.display : Display= display
        self.controller : Controller = controller
        self.device : Device= device
        self.theme : Theme= theme
        self.view_creator = ViewCreator(display,controller,device,theme)


    def run_popup_menu_selection(self):
        popup_options = []
        popup_options.append(GridOrListEntry(
            primary_text="Rom Search",
            image_path=self.theme.settings,
            image_path_selected=self.theme.settings_selected,
            description="",
            icon=self.theme.settings,
            value="Rom Search"
        ))

        popup_options.append(GridOrListEntry(
            primary_text="Future Option 2",
            image_path=self.theme.settings,
            image_path_selected=self.theme.settings_selected,
            description="",
            icon=self.theme.settings,
            value="Future Option 2"
        ))
        popup_options.append(GridOrListEntry(
            primary_text="Future Option 3",
            image_path=self.theme.settings,
            image_path_selected=self.theme.settings_selected,
            description="",
            icon=self.theme.settings,
            value="Future Option 3"
        ))
        popup_options.append(GridOrListEntry(
            primary_text="Future Option 4",
            image_path=self.theme.settings,
            image_path_selected=self.theme.settings_selected,
            description="",
            icon=self.theme.settings,
            value="Future Option 3"
        ))
        popup_options.append(GridOrListEntry(
            primary_text="Future Option 5",
            image_path=self.theme.settings,
            image_path_selected=self.theme.settings_selected,
            description="",
            icon=self.theme.settings,
            value="Future Option 3"
        ))
        popup_options.append(GridOrListEntry(
            primary_text="Future Option 6",
            image_path=self.theme.settings,
            image_path_selected=self.theme.settings_selected,
            description="",
            icon=self.theme.settings,
            value="Future Option 3"
        ))
        popup_options.append(GridOrListEntry(
            primary_text="Future Option 7",
            image_path=self.theme.settings,
            image_path_selected=self.theme.settings_selected,
            description="",
            icon=self.theme.settings,
            value="Future Option 3"
        ))
        popup_view = self.view_creator.create_view(
            view_type=ViewType.POPUP_TEXT_LIST_VIEW,
            options=popup_options,
            top_bar_text="Main Menu Sub Options",
            selected_index=0,
            cols=self.theme.popup_menu_cols,
            rows=self.theme.popup_menu_rows)
        
        while (popup_selection := popup_view.get_selection()):
            if(popup_selection.get_input() is not None):
                break
        
        if(popup_selection.get_input() is not None):
            popup_view.view_finished()

        if(ControllerInput.A == popup_selection.get_input()): 
            if("Rom Search" == popup_selection.get_selection().get_primary_text()):
                search_txt = OnScreenKeyboard(self.display,self.controller,self.device,self.theme).get_input("Game Search:")
                if(search_txt is not None):
                    SearchedRomsMenu(self.display,self.controller,self.device,self.theme, search_txt.upper()).run_rom_selection()
