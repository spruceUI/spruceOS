
import os
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.on_screen_keyboard import OnScreenKeyboard
from menus.settings import settings_menu
from menus.settings.display_settings_menu import DisplaySettingsMenu
from menus.settings.time_settings_menu import TimeSettingsMenu
from views.grid_or_list_entry import GridOrListEntry


class ExtraSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()
        self.on_screen_keyboard = OnScreenKeyboard()

    def reboot(self, input: ControllerInput):
        if(ControllerInput.A == input):
            Device.run_app(Device.reboot_cmd())

    def launch_display_settings(self,input):
        if(ControllerInput.A == input):
            DisplaySettingsMenu().show_menu()


    def launch_time_settings(self,input):
        if(ControllerInput.A == input):
            TimeSettingsMenu().show_menu()

    def launch_stock_os_menu(self,input):
        if(ControllerInput.A == input):
            Device.launch_stock_os_menu()

    def calibrate_sticks(self,input):
        if(ControllerInput.A == input):
            Device.calibrate_sticks()


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
