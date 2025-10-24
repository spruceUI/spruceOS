
import os
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.on_screen_keyboard import OnScreenKeyboard
from menus.language.language import Language
from menus.settings import settings_menu
from menus.settings.controller_settings_menu import ControllerSettingsMenu
from menus.settings.display_settings_menu import DisplaySettingsMenu
from menus.settings.game_select_settings_menu import GameSelectSettingsMenu
from menus.settings.game_switcher_settings_menu import GameSwitcherSettingsMenu
from menus.settings.language_menu import LanguageMenu
from menus.settings.game_system_select_settings_menu import GameSystemSelectSettingsMenu
from menus.settings.time_settings_menu import TimeSettingsMenu
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry


class ExtraSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()
        self.on_screen_keyboard = OnScreenKeyboard()

    def reboot(self, input: ControllerInput):
        if(ControllerInput.A == input):
            Device.run_cmd(Device.reboot_cmd())

    def launch_display_settings(self,input):
        if(ControllerInput.A == input):
            DisplaySettingsMenu().show_menu()

    def launch_time_settings(self,input):
        if(ControllerInput.A == input):
            TimeSettingsMenu().show_menu()

    def launch_game_system_select_settings(self,input):
        if(ControllerInput.A == input):
            if(GameSystemSelectSettingsMenu().show_menu()):
                self.theme_changed = True
                self.theme_ever_changed = True

    def launch_game_select_settings(self,input):
        if(ControllerInput.A == input):
            if(GameSelectSettingsMenu().show_menu()):
                self.theme_changed = True
                self.theme_ever_changed = True

    def launch_stock_os_menu(self,input):
        if(ControllerInput.A == input):
            Device.launch_stock_os_menu()

    def launch_controller_settings(self,input):
        if(ControllerInput.A == input):
            ControllerSettingsMenu().show_menu()

    def launch_gammeswitcher_settings(self,input):
        if(ControllerInput.A == input):
            GameSwitcherSettingsMenu().show_menu()

    def change_language_setting(self, input):
        if (ControllerInput.A == input):
            lang = LanguageMenu().ask_user_for_language()
            if (lang is not None):
                PyUiConfig.set_language(lang)
                Language.load()

    def resize_boxart(self, input):
        if (ControllerInput.A == input):
            from games.utils.box_art_resizer import BoxArtResizer
            BoxArtResizer.patch_boxart()
            
    def build_options_list(self):
        option_list = []
        
        option_list.append(
                GridOrListEntry(
                        primary_text="Display Settings",
                        value_text=None,
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.launch_display_settings
                    )
            )
        
        option_list.append(
                GridOrListEntry(
                        primary_text="Time Settings",
                        value_text=None,
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.launch_time_settings
                    )
            )
        
        option_list.append(
                GridOrListEntry(
                        primary_text="Game System Select Settings",
                        value_text=None,
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.launch_game_system_select_settings
                    )
            )
        
        option_list.append(
                GridOrListEntry(
                        primary_text="Game Select Settings",
                        value_text=None,
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.launch_game_select_settings
                    )
            )
        
        if(Device.supports_image_resizing()):
            option_list.append(
                GridOrListEntry(
                    primary_text="Resize Boxart",
                    value_text=None,
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value=self.resize_boxart
                )
            )        

        if(PyUiConfig.allow_pyui_game_switcher()):
            option_list.append(
                    GridOrListEntry(
                            primary_text="Game Switcher Settings",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.launch_gammeswitcher_settings
                    )
            )

        option_list.append(
                GridOrListEntry(
                        primary_text="Controller Settings",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.launch_controller_settings
                )
        )


        option_list.extend(Device.get_extra_settings_options())

        option_list.append(
                GridOrListEntry(
                        primary_text="Reboot",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.reboot
                )
        )

        option_list.append(
            GridOrListEntry(
                primary_text="Language",
                value_text=None,
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.change_language_setting
            )
        )        

                    
        if(PyUiConfig.include_stock_os_launch_option()):
            option_list.append(
                    GridOrListEntry(
                            primary_text="Stock OS Menu",
                            value_text=None,
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.launch_stock_os_menu
                        )
                )



        return option_list
