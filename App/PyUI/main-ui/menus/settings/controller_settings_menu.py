
from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

class ControllerSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def calibrate_sticks(self,input):
        if(ControllerInput.A == input):
            Device.get_device().calibrate_sticks()

    def remap_buttons(self,input):
        if(ControllerInput.A == input):
            Device.get_device().remap_buttons()

    def build_options_list(self):
        option_list = []
        
        if(Device.get_device().supports_analog_calibration()):
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.calibrate_analog_sticks(),
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
                        primary_text=Language.remap_buttons(),
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.remap_buttons
                )
        )

        option_list.append(
            self.build_numeric_entry(
                primary_text=Language.input_rate_limit_ms(),
                get_value_func=Device.get_device().get_system_config().get_input_rate_limit_ms,
                set_value_func=Device.get_device().get_system_config().set_input_rate_limit_ms,
            )
        )
        return option_list
