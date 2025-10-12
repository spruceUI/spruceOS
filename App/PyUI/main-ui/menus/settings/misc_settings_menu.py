
import os
from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from menus.settings.theme.list_of_options_selection_menu import ListOfOptionsSelectionMenu
from menus.settings.timezone_menu import TimezoneMenu
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry


GAME_SYSTEM_SORT_MODE_OPTIONS = ["Alphabetical","ReleaseYear","Brand","Type","SortOrderKey"]

class MiscSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()
    
    def change_game_system_sort_mode(self, input):
        if (ControllerInput.DPAD_LEFT == input):
            PyUiConfig.set_game_system_sort_mode(self.get_next_entry(PyUiConfig.game_system_sort_mode(),GAME_SYSTEM_SORT_MODE_OPTIONS,-1))
        elif (ControllerInput.DPAD_RIGHT == input):
            PyUiConfig.set_game_system_sort_mode(self.get_next_entry(PyUiConfig.game_system_sort_mode(),GAME_SYSTEM_SORT_MODE_OPTIONS,+1))
        elif (ControllerInput.A):
            selected_index = ListOfOptionsSelectionMenu().get_selected_option_index(GAME_SYSTEM_SORT_MODE_OPTIONS, "Game System Sort Mode")
            if(selected_index is not None):
                PyUiConfig.set_game_system_sort_mode(GAME_SYSTEM_SORT_MODE_OPTIONS[selected_index])

        self.theme_changed = True
        self.theme_ever_changed = True
    
    def change_show_all_game_systems(self, input):
        if (ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input or ControllerInput.A == input):
            PyUiConfig.set_show_all_game_systems(not PyUiConfig.show_all_game_systems())
            self.theme_changed = True
            self.theme_ever_changed = True

    def build_options_list(self):
        option_list = []

        option_list.append(
            GridOrListEntry(
                primary_text="Game System Sorting",
                value_text="<    " + PyUiConfig.game_system_sort_mode()+ "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.change_game_system_sort_mode
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text="Show All Systems",
                value_text="<    " +
                ("On" if PyUiConfig.show_all_game_systems() else "Off") + "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.change_show_all_game_systems
            )
        )

        return option_list
