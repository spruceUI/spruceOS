
import os
from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from views.grid_or_list_entry import GridOrListEntry


class DisplaySettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()
    
    def brightness_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.lower_brightness()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.raise_brightness()

    def contrast_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.lower_contrast()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.raise_contrast()

    def saturation_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.lower_saturation()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.raise_saturation()
    
    def lumination_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.lower_lumination()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.raise_lumination()
    
    def hue_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.lower_hue()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.raise_hue()



    def build_options_list(self):
        option_list = []

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
                        primary_text="Brightness",
                        value_text="<    " + str(Device.get_brightness()) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.brightness_adjust
                    )
            )
        option_list.append(
                GridOrListEntry(
                        primary_text="Contrast",
                        value_text="<    " + str(Device.get_contrast()) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.contrast_adjust
                    )
            )
        option_list.append(
                GridOrListEntry(
                        primary_text="Saturation",
                        value_text="<    " + str(Device.get_saturation()) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.saturation_adjust
                    )
            )          
        
        option_list.append(
                GridOrListEntry(
                        primary_text="Hue",
                        value_text="<    " + str(Device.get_hue()) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.hue_adjust
                    )
            )          
        
        return option_list
