from controller.controller_inputs import ControllerInput
from devices.device import Device
from devices.device_display_config_helper import DeviceDisplayConfigHelper
from menus.settings import settings_menu
from menus.language.language import Language
from views.grid_or_list_entry import GridOrListEntry


class SharedDisplaySettingsMenu(settings_menu.SettingsMenu):

    SETTINGS_CATEGORY = ""

    def _profile_name(self):
        return (
            "nightmode"
            if self.SETTINGS_CATEGORY == "Night Mode Settings"
            else "desired_display"
        )

    def _get_profile_value(self, name):
        config = Device.get_device().get_system_config()
        return getattr(config, f"get_{self._profile_name()}_{name}")()

    def _set_profile_value(self, name, value):
        config = Device.get_device().get_system_config()
        getattr(config, f"set_{self._profile_name()}_{name}")(value)

    def _adjust_calibration(self, input, name, maximum=20):
        incrementer = 0

        if(ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input):
            incrementer = -1
        elif(ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input):
            incrementer = 1

        if incrementer == 0:
            return

        value = max(0, min(maximum, int(self._get_profile_value(name)) + incrementer))
        self._set_profile_value(name, value)

        if self.is_display_mode_active():
            DeviceDisplayConfigHelper.display_mode_changed()

    def backlight_adjust(self, input: ControllerInput):
        self._adjust_calibration(input, "backlight", maximum=10)

    def brightness_adjust(self, input: ControllerInput):
        self._adjust_calibration(input, "brightness")

    def contrast_adjust(self, input: ControllerInput):
        self._adjust_calibration(input, "contrast")

    def saturation_adjust(self, input: ControllerInput):
        self._adjust_calibration(input, "saturation")
    
    def hue_adjust(self, input: ControllerInput):
        self._adjust_calibration(input, "hue")
    
    def adjust_rgb(self, input: ControllerInput, name):
        delta = 0
        if(ControllerInput.DPAD_LEFT == input):
            delta = -1
        elif(ControllerInput.L1== input):
            delta = -10
        elif(ControllerInput.DPAD_RIGHT == input):
            delta = +1
        elif(ControllerInput.R1 == input):
            delta = +10

        if delta == 0:
            return

        new_value = int(self._get_profile_value(name)) + delta
        if(new_value < 0): 
            new_value = 255
        elif(new_value > 255): 
            new_value = 0
        
        self._set_profile_value(name, new_value)
        if self.is_display_mode_active():
            DeviceDisplayConfigHelper.display_mode_changed()

    def is_display_mode_active(self):
        night_mode_active = Device.get_device().get_system_config().get_nightmode_active()
        return night_mode_active == (self.SETTINGS_CATEGORY == "Night Mode Settings")

    def _entry_value_text(self, name):
        return "<    " + str(self._get_profile_value(name)) + "    >"

    def build_options_list(self):
        option_list = []

        option_list.append(
                GridOrListEntry(
                        primary_text=Language.backlight(),
                        value_text=self._entry_value_text("backlight"),
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.backlight_adjust
                    )
            )

        if(Device.get_device().supports_brightness_calibration()):
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.brightness(),
                            value_text=self._entry_value_text("brightness"),
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
                            value_text=self._entry_value_text("contrast"),
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
                            value_text=self._entry_value_text("saturation"),
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
                            value_text=self._entry_value_text("hue"),
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
                            value_text=self._entry_value_text("red"),
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=lambda input_value: self.adjust_rgb(input_value, "red")
                        )
                )          
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.blue(),
                            value_text=self._entry_value_text("blue"),
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=lambda input_value: self.adjust_rgb(input_value, "blue")
                        )
                )          
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.green(),
                            value_text=self._entry_value_text("green"),
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=lambda input_value: self.adjust_rgb(input_value, "green")
                        )
                )          
        
        return option_list
