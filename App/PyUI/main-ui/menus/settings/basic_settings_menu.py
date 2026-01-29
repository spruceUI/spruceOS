
import os
import sys
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from menus.language.language import Language
from menus.settings import settings_menu
from menus.settings.about_menu import AboutMenu
from menus.settings.extra_settings_menu import ExtraSettingsMenu
from menus.settings.bluetooth_menu import BluetoothMenu
from menus.settings.sound_settings import SoundSettings
from menus.settings.tasks_menu import TasksMenu
from menus.settings.theme.theme_selection_menu import ThemeSelectionMenu
from menus.settings.theme.theme_settings_menu import ThemeSettingsMenu
from menus.settings.wifi_menu import WifiMenu
from themes.theme import Theme
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class BasicSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()
        self.wifi_menu = Device.get_device().get_wifi_menu()
        self.bt_menu = BluetoothMenu()
        self.theme_ever_changed = False

    def shutdown(self, input: ControllerInput):
        if(ControllerInput.A == input):
           Device.get_device().prompt_power_down()
    
    def lumination_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.get_device().lower_lumination()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.get_device().raise_lumination()
        
    def volume_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input):
            Device.get_device().change_volume(-5)
        elif(ControllerInput.L1 == input):
            Device.get_device().change_volume(-5)
        elif(ControllerInput.DPAD_RIGHT == input):
            Device.get_device().change_volume(+5)
        elif(ControllerInput.R1 == input):
            Device.get_device().change_volume(+5)

    def show_wifi_menu(self, input):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input):
            if(Device.get_device().is_wifi_enabled()):
                Device.get_device().disable_wifi()
            else:
                Device.get_device().enable_wifi()

        if(ControllerInput.A == input):
            self.wifi_menu.show_wifi_menu()

    def show_bt_menu(self, input):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input):
            if(Device.get_device().is_bluetooth_enabled()):
                Device.get_device().disable_bluetooth()
            else:
                Device.get_device().enable_bluetooth()
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
        selected_index = theme_folders.index(Device.get_device().get_system_config().get_theme())
        if(ControllerInput.DPAD_LEFT == input):
            selected_index-=1
            if(selected_index < 0):
                selected_index = len(theme_folders) -1
        elif(ControllerInput.DPAD_RIGHT == input):
            selected_index+=1
            if(selected_index == len(theme_folders)):
                selected_index = 0
        elif(ControllerInput.X == input and not Device.get_device().get_system_config().simple_mode_enabled()):
            ThemeSettingsMenu().show_theme_options_menu()
        elif(ControllerInput.A == input):
            selected_index = ThemeSelectionMenu().get_selected_option_index(theme_folders, "Themes")


        if(selected_index is not None):
            Theme.set_theme_path(os.path.join(PyUiConfig.get("themeDir"), theme_folders[selected_index]), Device.get_device().screen_width(), Device.get_device().screen_height())
            Display.init_fonts()   
            Device.get_device().get_system_config().set_theme(theme_folders[selected_index])
            Device.get_device().set_theme(os.path.join(PyUiConfig.get("themeDir"), theme_folders[selected_index]))
            self.theme_changed = True
            Display.restore_bg()

    def launch_extra_settings(self,input):
        if(ControllerInput.A == input):
            if(ExtraSettingsMenu().show_menu()):
                self.theme_changed = True

    def launch_tasks(self,input):
        if(ControllerInput.A == input):
            TasksMenu().show_menu()

    def launch_about(self,input):
        if(ControllerInput.A == input):
            AboutMenu().show_menu()

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
                        primary_text=Language.power_off(),
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.shutdown
                    )
            )
        option_list.append(
                GridOrListEntry(
                        primary_text=Language.backlight(),
                        value_text="<    " + str(Device.get_device().lumination()) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.lumination_adjust
                    )
            )

        if(Device.get_device().supports_volume()):
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.volume(),
                            value_text="<    " + str(Device.get_device().get_volume()//5) + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.volume_adjust
                        )
                )
        

        if(not Device.get_device().get_system_config().simple_mode_enabled()):

            if(Device.get_device().supports_wifi() and self.wifi_menu is not None):
                option_list.append(
                        GridOrListEntry(
                                primary_text=Language.wifi(),
                                value_text="<    " + (Device.get_device().get_ip_addr_text()) + "    >",
                                image_path=None,
                                image_path_selected=None,
                                description=None,
                                icon=None,
                                value=self.show_wifi_menu
                            )
                    )
            
            if(Device.get_device().get_bluetooth_scanner() is not None):
                option_list.append(
                        GridOrListEntry(
                                primary_text=Language.bluetooth(),
                                value_text="<    " + ("On" if Device.get_device().is_bluetooth_enabled() else "Off") + "    >",
                                image_path=None,
                                image_path_selected=None,
                                description=None,
                                icon=None,
                                value=self.show_bt_menu
                            )
                    )
                
        option_list.append(
                GridOrListEntry(
                        primary_text=Language.theme(),
                        value_text="<    " + Device.get_device().get_system_config().get_theme() + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.change_theme
                    )
        )
            

        if(not Device.get_device().get_system_config().simple_mode_enabled()):
            option_list.append(
                        GridOrListEntry(
                                primary_text=Language.theme_settings(),
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
                    primary_text=Language.sound_settings(),
                    value_text="",
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value=self.launch_sound_options
                )
            )

            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.additional_settings(),
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
                            primary_text=Language.tasks(),
                            value_text=None,
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.launch_tasks
                        )
                )

            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.aboutThisDevice(),
                            value_text=None,
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.launch_about
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
