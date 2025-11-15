
import os
import sys
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from menus.language.language import Language
from menus.settings import settings_menu
from menus.settings.cfw_system_settings_menu import CfwSystemSettingsMenu
from menus.settings.extra_settings_menu import ExtraSettingsMenu
from menus.settings.bluetooth_menu import BluetoothMenu
from menus.settings.sound_settings import SoundSettings
from menus.settings.theme.list_of_options_selection_menu import ListOfOptionsSelectionMenu
from menus.settings.theme.theme_settings_menu import ThemeSettingsMenu
from menus.settings.wifi_menu import WifiMenu
from themes.theme import Theme
from utils.cfw_system_config import CfwSystemConfig
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class BasicSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()
        self.wifi_menu = WifiMenu()
        self.bt_menu = BluetoothMenu()
        self.theme_ever_changed = False

    def shutdown(self, input: ControllerInput):
        if(ControllerInput.A == input):
           Device.prompt_power_down()
    
    def lumination_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.lower_lumination()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.raise_lumination()
        
    def volume_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input):
            Device.change_volume(-5)
        elif(ControllerInput.L1 == input):
            Device.change_volume(-5)
        elif(ControllerInput.DPAD_RIGHT == input):
            Device.change_volume(+5)
        elif(ControllerInput.R1 == input):
            Device.change_volume(+5)

    def show_wifi_menu(self, input):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input):
            if(Device.is_wifi_enabled()):
                Device.disable_wifi()
            else:
                Device.enable_wifi()

        if(ControllerInput.A == input):
            self.wifi_menu.show_wifi_menu()

    def show_bt_menu(self, input):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input):
            if(Device.is_bluetooth_enabled()):
                Device.disable_bluetooth()
            else:
                Device.enable_bluetooth()
        else:
            self.bt_menu.show_bluetooth_menu()

    def get_theme_folders(self):
        theme_dir = PyUiConfig.get("themeDir")
        return sorted(
            [
                name for name in os.listdir(theme_dir)
                if os.path.isdir(os.path.join(theme_dir, name)) and
                os.path.isfile(os.path.join(theme_dir, name, "config.json"))
            ]
        )    
    
    
    def change_theme(self, input):
        self.theme_ever_changed = True
        theme_folders = self.get_theme_folders()
        selected_index = theme_folders.index(Device.get_system_config().get_theme())
        if(ControllerInput.DPAD_LEFT == input):
            selected_index-=1
            if(selected_index < 0):
                selected_index = len(theme_folders) -1
        elif(ControllerInput.DPAD_RIGHT == input):
            selected_index+=1
            if(selected_index == len(theme_folders)):
                selected_index = 0
        elif(ControllerInput.X == input):
            ThemeSettingsMenu().show_theme_options_menu()
        elif(ControllerInput.A == input):
            selected_index = ListOfOptionsSelectionMenu().get_selected_option_index(theme_folders, "Themes")


        if(selected_index is not None):
            Theme.set_theme_path(os.path.join(PyUiConfig.get("themeDir"), theme_folders[selected_index]), Device.screen_width(), Device.screen_height())
            Display.init_fonts()   
            Device.get_system_config().set_theme(theme_folders[selected_index])
            Device.set_theme(os.path.join(PyUiConfig.get("themeDir"), theme_folders[selected_index]))
            self.theme_changed = True
            Display.restore_bg()


    def launch_cfw_system_settings(self,input):
        if(ControllerInput.A == input):
            CfwSystemSettingsMenu().show_menu()

    def launch_extra_settings(self,input):
        if(ControllerInput.A == input):
            if(ExtraSettingsMenu().show_menu()):
                self.theme_changed = True

    def launch_theme_settings(self,input):
        if(ControllerInput.A == input):
            ThemeSettingsMenu().show_theme_options_menu()

    def exit(self,input):
        if(ControllerInput.A == input):
            sys.exit()

            
    def launch_sound_options(self, input):
        if (input == ControllerInput.A):
            SoundSettings().show_menu()


    def build_options_list(self):
        option_list = []
        option_list.append(
                GridOrListEntry(
                        primary_text="Power Off",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.shutdown
                    )
            )
        option_list.append(
                GridOrListEntry(
                        primary_text="Backlight",
                        value_text="<    " + str(Device.lumination()) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.lumination_adjust
                    )
            )

        if(Device.supports_volume()):
            option_list.append(
                    GridOrListEntry(
                            primary_text="Volume",
                            value_text="<    " + str(Device.get_volume()//5) + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.volume_adjust
                        )
                )
        
        option_list.append(
                    GridOrListEntry(
                            primary_text="Theme",
                            value_text="<    " + Device.get_system_config().get_theme() + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.change_theme
                        )
        )

        if(not Device.get_system_config().simple_mode_enabled()):

            if(Device.supports_wifi()):
                option_list.append(
                        GridOrListEntry(
                                primary_text="WiFi",
                                value_text="<    " + (Device.get_ip_addr_text()) + "    >",
                                image_path=None,
                                image_path_selected=None,
                                description=None,
                                icon=None,
                                value=self.show_wifi_menu
                            )
                    )
            
            if(Device.get_bluetooth_scanner() is not None):
                option_list.append(
                        GridOrListEntry(
                                primary_text="Bluetooth",
                                value_text="<    " + ("On" if Device.is_bluetooth_enabled() else "Off") + "    >",
                                image_path=None,
                                image_path_selected=None,
                                description=None,
                                icon=None,
                                value=self.show_bt_menu
                            )
                    )
                
            
            option_list.append(
                    GridOrListEntry(
                            primary_text="Theme Settings",
                            value_text=None,
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.launch_theme_settings
                        )
                )

            option_list.append(
                GridOrListEntry(
                    primary_text="Sound Settings",
                    value_text="",
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value=self.launch_sound_options
                )
            )

            if(len(CfwSystemConfig.get_categories()) > 0):
                option_list.append(
                    GridOrListEntry(
                                primary_text=PyUiConfig.get_cfw_name() + " Settings",
                                value_text=None,
                                image_path=None,
                                image_path_selected=None,
                                description=None,
                                icon=None,
                                value=self.launch_cfw_system_settings
                    )
                )

            option_list.append(
                    GridOrListEntry(
                            primary_text="Extra Settings",
                            value_text=None,
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.launch_extra_settings
                        )
                )

            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.exit_py_ui(),
                            value_text=None,
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.exit
                        )
                )
        

        return option_list


    def show_menu(self) :
        selected = Selection(None, None, 0)
        list_view = None
        self.theme_changed = False
        while(selected is not None):
            option_list = self.build_options_list()
            
            if(self.theme_changed):
                self.theme_ever_changed = True

            if(list_view is None or self.theme_changed):
                Display.clear_text_cache()
                list_view = ViewCreator.create_view(
                    view_type=ViewType.ICON_AND_DESC,
                    top_bar_text="Settings", 
                    options=option_list,
                    selected_index=selected.get_index())
                    
                self.theme_changed = False
            else:
                list_view.set_options(option_list)

            control_options = [ControllerInput.A,ControllerInput.X, ControllerInput.DPAD_LEFT, ControllerInput.DPAD_RIGHT,
                                                  ControllerInput.L1, ControllerInput.R1]
            selected = list_view.get_selection(control_options)

            if(Theme.skip_main_menu() and (ControllerInput.L1 == selected.get_input() or ControllerInput.B == selected.get_input())):
                if(self.theme_ever_changed):
                    os._exit(0)
                return selected.get_input()
            if(Theme.skip_main_menu() and ControllerInput.R1 == selected.get_input()):
                if(self.theme_ever_changed):
                    os._exit(0)
                return ControllerInput.R1
            elif(selected.get_input() in control_options):
                selected.get_selection().get_value()(selected.get_input())
            elif(ControllerInput.B == selected.get_input()):
                if(not Theme.skip_main_menu()):
                    selected = None
        
        if(self.theme_ever_changed):
            os._exit(0)
        return False #shouldnt need to do this but jic
