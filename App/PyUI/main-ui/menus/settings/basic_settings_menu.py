
import os
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from menus.settings import settings_menu
from menus.settings.advance_settings_menu import AdvanceSettingsMenu
from menus.settings.bluetooth_menu import BluetoothMenu
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
        self.wifi_menu = WifiMenu()
        self.bt_menu = BluetoothMenu()
        self.advance_settings_menu = AdvanceSettingsMenu()
        self.anything_theme_related_changed = False

    def shutdown(self, input: ControllerInput):
        if(ControllerInput.A == input):
           Device.run_app(Device.power_off_cmd())
    
    def reboot(self, input: ControllerInput):
        if(ControllerInput.A == input):
            Device.run_app(Device.reboot_cmd())
    
    def lumination_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.lower_lumination()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.raise_lumination()
        
    def volume_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input):
            Device.change_volume(-10)
        elif(ControllerInput.L1 == input):
            Device.change_volume(-1)
        elif(ControllerInput.DPAD_RIGHT == input):
            Device.change_volume(+10)
        elif(ControllerInput.R1 == input):
            Device.change_volume(+1)

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
        theme_folders = self.get_theme_folders()
        selected_index = theme_folders.index(PyUiConfig.get("theme"))

        if(ControllerInput.DPAD_LEFT == input):
            selected_index-=1
            if(selected_index < 0):
                selected_index = len(theme_folders) -1
        elif(ControllerInput.DPAD_RIGHT == input):
            selected_index+=1
            if(selected_index == len(theme_folders)):
                selected_index = 0
        elif(ControllerInput.A == input):
            ThemeSettingsMenu().show_theme_options_menu()

        Theme.set_theme_path(os.path.join(PyUiConfig.get("themeDir"), theme_folders[selected_index]), Device.screen_width(), Device.screen_height())
        Display.init_fonts()   
        PyUiConfig.set("theme",theme_folders[selected_index])
        PyUiConfig.save()      
        self.theme_changed = True

    def launch_advance_settings(self,input):
        if(ControllerInput.A == input):
            self.advance_settings_menu.show_menu()


    def launch_stock_os_menu(self,input):
        if(ControllerInput.A == input):
            Device.launch_stock_os_menu()

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

        option_list.append(
                GridOrListEntry(
                        primary_text="Volume",
                        value_text="<    " + str(Device.get_volume()) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.volume_adjust
                    )
            )
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
                        primary_text="Theme",
                        value_text="<    " + PyUiConfig.get("theme") + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.change_theme
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
            
        option_list.append(
                GridOrListEntry(
                        primary_text="Advanced Settings",
                        value_text=None,
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.launch_advance_settings
                    )
            )

        return option_list


    def show_menu(self) :
        selected = Selection(None, None, 0)
        list_view = None
        self.theme_changed = False
        self.anything_theme_related_changed = True
        while(selected is not None):
            option_list = self.build_options_list()
            

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

            control_options = [ControllerInput.A, ControllerInput.DPAD_LEFT, ControllerInput.DPAD_RIGHT,
                                                  ControllerInput.L1, ControllerInput.R1]
            selected = list_view.get_selection(control_options)

            if(selected.get_input() in control_options):
                selected.get_selection().get_value()(selected.get_input())
            elif(ControllerInput.B == selected.get_input()):
                selected = None
        
        return self.anything_theme_related_changed

