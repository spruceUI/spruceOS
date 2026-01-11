
from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

class DisplaySettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()
    
    def brightness_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.get_device().lower_brightness()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.get_device().raise_brightness()

    def contrast_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.get_device().lower_contrast()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.get_device().raise_contrast()

    def saturation_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.get_device().lower_saturation()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.get_device().raise_saturation()
    
    def lumination_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.get_device().lower_lumination()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.get_device().raise_lumination()
    
    def hue_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.get_device().lower_hue()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.get_device().raise_hue()

    
    def hue_adjust(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            Device.get_device().lower_hue()
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            Device.get_device().raise_hue()

    def adjust_rgb(self, input: ControllerInput, getter, setter):
        delta = 0
        if(ControllerInput.DPAD_LEFT == input):
            delta = -1
        elif(ControllerInput.L1== input):
            delta = -10
        elif(ControllerInput.DPAD_RIGHT == input):
            delta = +1
        elif(ControllerInput.R1 == input):
            delta = +10

        new_value = getter() + delta
        if(new_value < 0): 
            new_value = 255
        elif(new_value > 255): 
            new_value = 0
        
        setter(new_value)
            
    def build_options_list(self):
        option_list = []

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

        if(Device.get_device().supports_brightness_calibration()):
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.brightness(),
                            value_text="<    " + str(Device.get_device().brightness()) + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.brightness_adjust
                        )
                )
        if(Device.get_device().supports_contrast_calibration()):
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.contrast(),
                            value_text="<    " + str(Device.get_device().contrast()) + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.contrast_adjust
                        )
                )
        if(Device.get_device().supports_saturation_calibration()):
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.saturation(),
                            value_text="<    " + str(Device.get_device().saturation()) + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.saturation_adjust
                        )
                )          
        
        if(Device.get_device().supports_hue_calibration()):
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.hue(),
                            value_text="<    " + str(Device.get_device().hue()) + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.hue_adjust
                        )
                )          
        
        if(Device.get_device().supports_rgb_calibration()):
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.red(),
                            value_text="<    " + str(Device.get_device().get_disp_red()) + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=lambda input_value, getter=Device.get_device().get_disp_red, setter=Device.get_device().set_disp_red: self.adjust_rgb(input_value,getter,setter)
                        )
                )          
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.blue(),
                            value_text="<    " + str(Device.get_device().get_disp_blue()) + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=lambda input_value, getter=Device.get_device().get_disp_blue, setter=Device.get_device().set_disp_blue: self.adjust_rgb(input_value,getter,setter)
                        )
                )          
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.green(),
                            value_text="<    " + str(Device.get_device().get_disp_green()) + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=lambda input_value, getter=Device.get_device().get_disp_green, setter=Device.get_device().set_disp_green: self.adjust_rgb(input_value,getter,setter)
                        )
                )          
        
        return option_list
