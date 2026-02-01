
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.on_screen_keyboard import OnScreenKeyboard
from games.utils.box_art_resizer import BoxArtResizer
from menus.language.language import Language
from menus.settings import settings_menu
from menus.settings.animation_settings_menu import AnimationSettingsMenu
from menus.settings.cfw_system_settings_menu_for_category import CfwSystemSettingsMenuForCategory
from menus.settings.controller_settings_menu import ControllerSettingsMenu
from menus.settings.display_settings_menu import DisplaySettingsMenu
from menus.settings.game_art_display_settings_menu import GameArtDisplaySettingsMenu
from menus.settings.game_select_settings_menu import GameSelectSettingsMenu
from menus.settings.game_switcher_settings_menu import GameSwitcherSettingsMenu
from menus.settings.language_menu import LanguageMenu
from menus.settings.game_system_select_settings_menu import GameSystemSelectSettingsMenu
from menus.settings.time_settings_menu import TimeSettingsMenu
from utils.cfw_system_config import CfwSystemConfig
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry


class ExtraSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()
        self.on_screen_keyboard = OnScreenKeyboard()

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
            Device.get_device().launch_stock_os_menu()

    def launch_controller_settings(self,input):
        if(ControllerInput.A == input):
            ControllerSettingsMenu().show_menu()

    def launch_animation_settings(self,input):
        if(ControllerInput.A == input):
            AnimationSettingsMenu().show_menu()
            
    def launch_gammeswitcher_settings(self,input):
        if(ControllerInput.A == input):
            GameSwitcherSettingsMenu().show_menu()

    def change_language_setting(self, input):
        if (ControllerInput.A == input):
            lang = LanguageMenu().ask_user_for_language()
            if (lang is not None):
                PyUiConfig.set_language(lang)
                Language.load()

    def launch_game_art_display_settings(self,input):
        if(ControllerInput.A == input):
            GameArtDisplaySettingsMenu().show_menu()
    def resize_boxart(self, input):
        if (ControllerInput.A == input):
            BoxArtResizer.patch_boxart()
            

    def launch_settings_for_category(self,input, category):
        if(ControllerInput.A == input):
            CfwSystemSettingsMenuForCategory(category).show_menu()


    def is_excluded_setting(self,category):
        excluded_settings = [
            GameSwitcherSettingsMenu.SETTINGS_NAME
        ]
        return category in excluded_settings


    def build_options_list(self):
        option_list = []
        
        option_list.append(
                GridOrListEntry(
                        primary_text=Language.display_settings(),
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
                        primary_text=Language.animation_settings(),
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.launch_animation_settings
                )
        )

        option_list.append(
                GridOrListEntry(
                        primary_text=Language.time_settings(),
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
                        primary_text=Language.game_system_select_settings(),
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
                        primary_text=Language.game_select_settings(),
                        value_text=None,
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.launch_game_select_settings
                    )
            )
        
        if(PyUiConfig.allow_pyui_game_switcher()):
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.game_switcher_settings(),
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.launch_gammeswitcher_settings
                    )
            )
        option_list.append(
                GridOrListEntry(
                        primary_text=Language.game_art_display_settings(),
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.launch_game_art_display_settings
                )
        )

        option_list.append(
                GridOrListEntry(
                        primary_text=Language.controller_settings(),
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.launch_controller_settings
                )
        )

        option_list.extend(Device.get_device().get_extra_settings_options())

        option_list.append(
            GridOrListEntry(
                primary_text=Language.language_settings(),
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
                            primary_text=Language.stock_os_menu(),
                            value_text=None,
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.launch_stock_os_menu
                        )
                )

        
        for category in CfwSystemConfig.get_categories():
            menu_options = CfwSystemConfig.get_menu_options(category=category)
            contains_entry_for_device = False
            for name, option in menu_options.items():
                devices = option.get('devices')
                supported_device = not devices or Device.get_device().get_device_name() in devices
                if(supported_device):
                    contains_entry_for_device = True
                    break

            if(contains_entry_for_device and not self.is_excluded_setting(category)):
                option_list.append(
                        GridOrListEntry(
                                primary_text=category,
                                value_text=None,
                                image_path=None,
                                image_path_selected=None,
                                description=None,
                                icon=None,
                                value=lambda 
                                    input_value, 
                                    category=category: self.launch_settings_for_category(input_value, category)
                            )
                    )

      

        return option_list
