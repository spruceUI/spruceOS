
import os
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.on_screen_keyboard import OnScreenKeyboard
from menus.language.language import Language
from menus.settings import settings_menu
from menus.settings.display_settings_menu import DisplaySettingsMenu
from menus.settings.game_select_settings_menu import GameSelectSettingsMenu
from menus.settings.language_menu import LanguageMenu
from menus.settings.game_system_select_settings_menu import GameSystemSelectSettingsMenu
from menus.settings.time_settings_menu import TimeSettingsMenu
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry


class ControllerSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def calibrate_sticks(self,input):
        if(ControllerInput.A == input):
            Device.calibrate_sticks()

    def remap_buttons(self,input):
        if(ControllerInput.A == input):
            Device.remap_buttons()

    def build_options_list(self):
        option_list = []
        
        if(Device.supports_analog_calibration()):
            option_list.append(
                    GridOrListEntry(
                            primary_text="Calibrate Analog Sticks",
                            value_text=None,
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.calibrate_sticks
                        )
                )

        option_list.append(
                GridOrListEntry(
                        primary_text="Remap Buttons",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.remap_buttons
                )
        )

        return option_list
