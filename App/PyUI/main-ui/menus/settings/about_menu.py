
from asyncio import subprocess
from collections import defaultdict
import json
import os
from zipfile import Path
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from display.font_purpose import FontPurpose
from display.on_screen_keyboard import OnScreenKeyboard
from games.utils.box_art_resizer import BoxArtResizer
from menus.language.language import Language
from menus.settings import settings_menu
from menus.settings.cfw_system_settings_menu_for_category import CfwSystemSettingsMenuForCategory
from menus.settings.controller_settings_menu import ControllerSettingsMenu
from menus.settings.display_settings_menu import DisplaySettingsMenu
from menus.settings.game_art_display_settings_menu import GameArtDisplaySettingsMenu
from menus.settings.game_select_settings_menu import GameSelectSettingsMenu
from menus.settings.game_switcher_settings_menu import GameSwitcherSettingsMenu
from menus.settings.language_menu import LanguageMenu
from menus.settings.game_system_select_settings_menu import GameSystemSelectSettingsMenu
from menus.settings.modes_menu import ModesMenu
from menus.settings.time_settings_menu import TimeSettingsMenu
from option_select_ui import OptionSelectUI
from themes.theme import Theme
from utils.boxart.box_art_scraper import BoxArtScraper
from utils.cfw_system_config import CfwSystemConfig
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_type import ViewType


class AboutMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def do_nothing(self, input_value):
        pass

    def build_options_list(self):
        option_list = []

        for text, value in Device.get_about_info_entries():
            option_list.append(
                GridOrListEntry(
                    primary_text=text,
                    value_text=value,
                    description=None,
                    value=self.do_nothing
                    )
                )

            

        return option_list