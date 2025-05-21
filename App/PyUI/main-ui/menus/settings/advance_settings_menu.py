
import os
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.on_screen_keyboard import OnScreenKeyboard
from menus.settings import settings_menu
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry


class AdvanceSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()
        self.on_screen_keyboard = OnScreenKeyboard()

    def reboot(self, input: ControllerInput):
        if(ControllerInput.A == input):
            Device.run_app(Device.reboot_cmd())
    
    
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
    

    def show_on_screen_keyboard(self, input):
        PyUiLogger.get_logger().info(self.on_screen_keyboard.get_input("On Screen Keyboard Test"))

    def change_hold_delay(self, input):
        current_delay = PyUiConfig.get_turbo_delay_ms() * 1000

        if(ControllerInput.DPAD_LEFT == input):
            if(current_delay > 0):
                current_delay-=1
        elif(ControllerInput.DPAD_RIGHT == input):
            if(current_delay < 1000):
                current_delay+=1
        if(ControllerInput.L1 == input):
            if(current_delay > 0):
                current_delay-=100
        elif(ControllerInput.R1 == input):
            if(current_delay < 1000):
                current_delay+=100

        PyUiConfig.set_turbo_delay_ms(current_delay)
        PyUiConfig.save()


    def build_options_list(self):
        option_list = []

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
                        primary_text="Menu Turbo Delay (mS)",
                        value_text="<    " + str(int(PyUiConfig.get_turbo_delay_ms()*1000)) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.change_hold_delay
                    )
        )

        option_list.append(
                GridOrListEntry(
                        primary_text="On Screen Keyboard",
                        value_text=None,
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.show_on_screen_keyboard
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

            
        
        return option_list
