from controller.controller_inputs import ControllerInput
from devices.device import Device
from devices.device_display_config_helper import DeviceDisplayConfigHelper
from menus.settings import settings_menu
from menus.settings.desired_display_settings_menu import DesiredDisplaySettingsMenu
from menus.settings.night_mode_settings_menu import NightModeSettingsMenu
from menus.language.language import Language
from views.grid_or_list_entry import GridOrListEntry

class DisplaySettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def toggle_night_mode(self, input):
        system_config = Device.get_device().get_system_config()
        current_value = system_config.get_nightmode_active()

        if (ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            value = False
        elif (ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            value = True
        elif ControllerInput.A == input:
            value = not current_value
        else:
            return
        system_config.set_nightmode_active(value)

        DeviceDisplayConfigHelper.display_mode_changed()

    def launch_display_settings(self,input):
        if(ControllerInput.A == input):
            DesiredDisplaySettingsMenu().show_menu()

    def launch_night_mode_settings(self, input):
        if ControllerInput.A == input:
            NightModeSettingsMenu().show_menu()

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
                        primary_text=Language.night_mode(),
                        value_text="<    " + str(Device.get_device().get_system_config().get_nightmode_active()) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.toggle_night_mode
                    )
            )

        option_list.append(
                GridOrListEntry(
                        primary_text=Language.settings_category(NightModeSettingsMenu.SETTINGS_CATEGORY),
                        value_text=None,
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.launch_night_mode_settings
                    )
            )
    
        return option_list