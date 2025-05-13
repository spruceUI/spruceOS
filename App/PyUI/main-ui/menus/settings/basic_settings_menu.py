
import os
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from menus.settings import settings_menu
from menus.settings.advance_settings_menu import AdvanceSettingsMenu
from menus.settings.bluetooth_menu import BluetoothMenu
from menus.settings.wifi_menu import WifiMenu
from themes.theme import Theme
from utils.py_ui_config import PyUiConfig
from views.descriptive_list_view import DescriptiveListView
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class BasicSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme, config: PyUiConfig):
        super().__init__(
            display=display,
            controller=controller,
            device=device,
            theme=theme,
            config=config)
        self.wifi_menu = WifiMenu(display,controller,device,theme)
        self.bt_menu = BluetoothMenu(display,controller,device,theme)
        self.advance_settings_menu = AdvanceSettingsMenu(display,controller,device,theme,config)

    def shutdown(self, input: ControllerInput):
        if(ControllerInput.A == input):
           self.device.run_app(self.device.power_off_cmd)
    
    def reboot(self, input: ControllerInput):
        if(ControllerInput.A == input):
            self.device.run_app(self.device.reboot_cmd)
    
    def lumination_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            self.device.lower_lumination()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            self.device.raise_lumination()
        
    def volume_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input):
            self.device.change_volume(-10)
        elif(ControllerInput.L1 == input):
            self.device.change_volume(-1)
        elif(ControllerInput.DPAD_RIGHT == input):
            self.device.change_volume(+10)
        elif(ControllerInput.R1 == input):
            self.device.change_volume(+1)

    def show_wifi_menu(self, input):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input):
            if(self.device.is_wifi_enabled()):
                self.device.disable_wifi()
            else:
                self.device.enable_wifi()
        else:
            self.wifi_menu.show_wifi_menu()

    def show_bt_menu(self, input):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input):
            if(self.device.is_bluetooth_enabled()):
                self.device.disable_bluetooth()
            else:
                self.device.enable_bluetooth()
        else:
            self.bt_menu.show_bluetooth_menu()

    def get_theme_folders(self):
        theme_dir = self.config["themeDir"]
        return sorted(
            [
                name for name in os.listdir(theme_dir)
                if os.path.isdir(os.path.join(theme_dir, name)) and
                os.path.isfile(os.path.join(theme_dir, name, "config.json"))
            ]
        )    
    
    def change_theme(self, input):
        theme_folders = self.get_theme_folders()
        selected_index = theme_folders.index(self.config["theme"])

        if(ControllerInput.DPAD_LEFT == input):
            selected_index-=1
            if(selected_index < 0):
                selected_index = len(theme_folders) -1
        elif(ControllerInput.DPAD_RIGHT == input):
            selected_index+=1
            if(selected_index == len(theme_folders)):
                selected_index = 0

        self.theme.set_theme_path(os.path.join(self.config["themeDir"], theme_folders[selected_index]))
        self.display.init_fonts()   
        self.config["theme"] = theme_folders[selected_index]
        self.config.save()      
        self.theme_changed = True

    def launch_advance_settings(self,input):
        if(ControllerInput.A == input):
            self.advance_settings_menu.show_menu()

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
                        value_text="<    " + str(self.device.lumination) + "    >",
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
                        value_text="<    " + str(self.device.get_volume()) + "    >",
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
                        value_text="<    " + ("On" if self.device.is_wifi_enabled() else "Off") + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.show_wifi_menu
                    )
            )
        option_list.append(
                GridOrListEntry(
                        primary_text="Bluetooth",
                        value_text="<    " + ("On" if self.device.is_bluetooth_enabled() else "Off") + "    >",
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
                        value_text="<    " + self.config["theme"] + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.change_theme
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
        while(selected is not None):
            option_list = self.build_options_list()
            

            if(list_view is None or self.theme_changed):
                list_view = self.view_creator.create_view(
                    view_type=ViewType.DESCRIPTIVE_LIST_VIEW,
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

