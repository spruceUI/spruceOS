
import os
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.resize_type import get_next_resize_type
from menus.settings import settings_menu
from themes.theme import Theme
from utils.cfw_system_config import CfwSystemConfig
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry


class GameSwitcherSettingsMenu(settings_menu.SettingsMenu):
    SETTINGS_NAME = "Game Switcher Settings"

    def __init__(self):
        super().__init__()

    def toggle_game_switcher(self, input):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input):
            Device.get_system_config().set_game_switcher_enabled(not Device.get_system_config().game_switcher_enabled())

    def update_game_switcher_game_count(self, input):
        if(ControllerInput.DPAD_LEFT == input):
            Device.get_system_config().set_game_switcher_game_count(Device.get_system_config().game_switcher_game_count() - 1)
        elif(ControllerInput.DPAD_RIGHT == input):
            Device.get_system_config().set_game_switcher_game_count(Device.get_system_config().game_switcher_game_count() + 1)

    def build_options_list(self):
        option_list = []
        
        option_list.append(
                GridOrListEntry(
                        primary_text="Hold Menu for GameSwitcher",
                        value_text="<    " + str(Device.get_system_config().game_switcher_enabled()) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.toggle_game_switcher
                    )
            )
            
        option_list.append(
                GridOrListEntry(
                        primary_text="Game Count",
                        value_text="<    " + str(Device.get_system_config().game_switcher_game_count()) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.update_game_switcher_game_count
                    )
            )

            
        option_list.append(
            self.build_enum_entry(
                primary_text="Full Screen Resize Type",
                get_value_func=Theme.get_resize_type_for_game_switcher,
                set_value_func=Theme.set_resize_type_for_game_switcher,
                get_next_enum_type=get_next_resize_type
            )
        )

        menu_options = self.build_options_list_from_config_menu_options(GameSwitcherSettingsMenu.SETTINGS_NAME)
        option_list.extend(menu_options)

        return option_list
