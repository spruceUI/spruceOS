"""
Display Test Menu for experimenting with display control settings
This menu allows testing brightness, contrast, saturation, hue, and RGB values
to find optimal settings for replacing keymon functionality.
"""

from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from views.grid_or_list_entry import GridOrListEntry
from menus.language.language import Language
from devices.utils.process_runner import ProcessRunner
from utils.logger import PyUiLogger


class DisplayTestMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()
        # Test values (0-20 range for config, converted to 0-100 for display)
        self.test_brightness = 9  # 9*5 = 45
        self.test_saturation = 9  # 9*5 = 45
        self.test_contrast = 10   # 10*5 = 50
        self.test_hue = 10        # 10*5 = 50
        self.test_red = 128
        self.test_green = 128
        self.test_blue = 128
        
    def apply_display_settings(self):
        """Apply current test values using display_control.sh"""
        try:
            # Convert config values (0-20) to display values (0-100)
            brightness_val = max(1, self.test_brightness) * 5  # Ensure minimum brightness
            saturation_val = self.test_saturation * 5
            contrast_val = max(1, self.test_contrast) * 5  # Ensure minimum contrast
            hue_val = self.test_hue * 5
            red_val = max(48, self.test_red)  # Ensure minimum red for visibility
            green_val = max(48, self.test_green)
            blue_val = max(48, self.test_blue)
            
            PyUiLogger.get_logger().info(
                f"Applying display settings: B={brightness_val} S={saturation_val} "
                f"C={contrast_val} H={hue_val} R={red_val} G={green_val} B={blue_val}"
            )
            
            ProcessRunner.run([
                "/mnt/SDCARD/spruce/scripts/display_control.sh",
                str(brightness_val),
                str(saturation_val),
                str(contrast_val),
                str(hue_val),
                str(red_val),
                str(green_val),
                str(blue_val)
            ])
            
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to apply display settings: {e}")

    def reset_to_defaults(self, input: ControllerInput):
        """Reset all values to defaults"""
        if ControllerInput.A == input:
            self.test_brightness = 9   # 45
            self.test_saturation = 9   # 45
            self.test_contrast = 10    # 50
            self.test_hue = 10         # 50
            self.test_red = 128
            self.test_green = 128
            self.test_blue = 128
            self.apply_display_settings()

    def apply_preset(self, input: ControllerInput, preset_name: str):
        """Apply predefined presets for testing"""
        if ControllerInput.A == input:
            if preset_name == "warm":
                # Warm/blue light filter
                self.test_red = 140
                self.test_green = 105
                self.test_blue = 70
            elif preset_name == "cool":
                # Cool/blue tint
                self.test_red = 100
                self.test_green = 128
                self.test_blue = 180
            elif preset_name == "night":
                # Very warm for night
                self.test_red = 160
                self.test_green = 90
                self.test_blue = 50
            elif preset_name == "vivid":
                # Brighter and more vivid
                self.test_brightness = 12  # 60
                self.test_saturation = 11  # 55
                self.test_contrast = 11    # 55
                
            self.apply_display_settings()

    def brightness_adjust(self, input: ControllerInput):
        if ControllerInput.DPAD_LEFT == input:
            self.test_brightness = max(0, self.test_brightness - 1)
            self.apply_display_settings()
        elif ControllerInput.L1 == input:
            self.test_brightness = max(0, self.test_brightness - 5)
            self.apply_display_settings()
        elif ControllerInput.DPAD_RIGHT == input:
            self.test_brightness = min(20, self.test_brightness + 1)
            self.apply_display_settings()
        elif ControllerInput.R1 == input:
            self.test_brightness = min(20, self.test_brightness + 5)
            self.apply_display_settings()

    def contrast_adjust(self, input: ControllerInput):
        if ControllerInput.DPAD_LEFT == input:
            self.test_contrast = max(0, self.test_contrast - 1)
            self.apply_display_settings()
        elif ControllerInput.L1 == input:
            self.test_contrast = max(0, self.test_contrast - 5)
            self.apply_display_settings()
        elif ControllerInput.DPAD_RIGHT == input:
            self.test_contrast = min(20, self.test_contrast + 1)
            self.apply_display_settings()
        elif ControllerInput.R1 == input:
            self.test_contrast = min(20, self.test_contrast + 5)
            self.apply_display_settings()

    def saturation_adjust(self, input: ControllerInput):
        if ControllerInput.DPAD_LEFT == input:
            self.test_saturation = max(0, self.test_saturation - 1)
            self.apply_display_settings()
        elif ControllerInput.L1 == input:
            self.test_saturation = max(0, self.test_saturation - 5)
            self.apply_display_settings()
        elif ControllerInput.DPAD_RIGHT == input:
            self.test_saturation = min(20, self.test_saturation + 1)
            self.apply_display_settings()
        elif ControllerInput.R1 == input:
            self.test_saturation = min(20, self.test_saturation + 5)
            self.apply_display_settings()

    def hue_adjust(self, input: ControllerInput):
        if ControllerInput.DPAD_LEFT == input:
            self.test_hue = max(0, self.test_hue - 1)
            self.apply_display_settings()
        elif ControllerInput.L1 == input:
            self.test_hue = max(0, self.test_hue - 5)
            self.apply_display_settings()
        elif ControllerInput.DPAD_RIGHT == input:
            self.test_hue = min(20, self.test_hue + 1)
            self.apply_display_settings()
        elif ControllerInput.R1 == input:
            self.test_hue = min(20, self.test_hue + 5)
            self.apply_display_settings()

    def rgb_adjust(self, input: ControllerInput, channel: str):
        """Adjust RGB channels"""
        delta = 0
        if ControllerInput.DPAD_LEFT == input:
            delta = -1
        elif ControllerInput.L1 == input:
            delta = -10
        elif ControllerInput.DPAD_RIGHT == input:
            delta = 1
        elif ControllerInput.R1 == input:
            delta = 10
        
        if delta != 0:
            if channel == "red":
                self.test_red = max(0, min(255, self.test_red + delta))
            elif channel == "green":
                self.test_green = max(0, min(255, self.test_green + delta))
            elif channel == "blue":
                self.test_blue = max(0, min(255, self.test_blue + delta))
            
            self.apply_display_settings()

    def build_options_list(self):
        option_list = []

        # Info header
        option_list.append(
            GridOrListEntry(
                primary_text="=== Display Control Test ===",
                value_text="",
                image_path=None,
                image_path_selected=None,
                description="Experiment with display settings",
                icon=None,
                value=lambda x: None
            )
        )

        # Brightness (Luma)
        option_list.append(
            GridOrListEntry(
                primary_text="Brightness (Luma)",
                value_text=f"<  {self.test_brightness * 5}  >",
                image_path=None,
                image_path_selected=None,
                description="6-100, Higher = brighter",
                icon=None,
                value=self.brightness_adjust
            )
        )

        # Saturation
        option_list.append(
            GridOrListEntry(
                primary_text="Saturation",
                value_text=f"<  {self.test_saturation * 5}  >",
                image_path=None,
                image_path_selected=None,
                description="0-100, Higher = more vivid, 0 = grayscale",
                icon=None,
                value=self.saturation_adjust
            )
        )

        # Contrast
        option_list.append(
            GridOrListEntry(
                primary_text="Contrast",
                value_text=f"<  {self.test_contrast * 5}  >",
                image_path=None,
                image_path_selected=None,
                description="0-100, Higher = more contrast",
                icon=None,
                value=self.contrast_adjust
            )
        )

        # Hue
        option_list.append(
            GridOrListEntry(
                primary_text="Hue",
                value_text=f"<  {self.test_hue * 5}  >",
                image_path=None,
                image_path_selected=None,
                description="0-100, Shifts color hue",
                icon=None,
                value=self.hue_adjust
            )
        )

        # RGB Controls
        option_list.append(
            GridOrListEntry(
                primary_text="Red Channel",
                value_text=f"<  {self.test_red}  >",
                image_path=None,
                image_path_selected=None,
                description="0-255, Red intensity",
                icon=None,
                value=lambda input: self.rgb_adjust(input, "red")
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text="Green Channel",
                value_text=f"<  {self.test_green}  >",
                image_path=None,
                image_path_selected=None,
                description="0-255, Green intensity",
                icon=None,
                value=lambda input: self.rgb_adjust(input, "green")
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text="Blue Channel",
                value_text=f"<  {self.test_blue}  >",
                image_path=None,
                image_path_selected=None,
                description="0-255, Blue intensity",
                icon=None,
                value=lambda input: self.rgb_adjust(input, "blue")
            )
        )

        # Presets
        option_list.append(
            GridOrListEntry(
                primary_text="--- Presets ---",
                value_text="",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=lambda x: None
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text="Reset to Defaults",
                value_text="[A] Apply",
                image_path=None,
                image_path_selected=None,
                description="45/45/50/50 RGB:128/128/128",
                icon=None,
                value=self.reset_to_defaults
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text="Warm Preset",
                value_text="[A] Apply",
                image_path=None,
                image_path_selected=None,
                description="Blue light filter RGB:140/105/70",
                icon=None,
                value=lambda input: self.apply_preset(input, "warm")
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text="Cool Preset",
                value_text="[A] Apply",
                image_path=None,
                image_path_selected=None,
                description="Cool tint RGB:100/128/180",
                icon=None,
                value=lambda input: self.apply_preset(input, "cool")
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text="Night Preset",
                value_text="[A] Apply",
                image_path=None,
                image_path_selected=None,
                description="Very warm RGB:160/90/50",
                icon=None,
                value=lambda input: self.apply_preset(input, "night")
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text="Vivid Preset",
                value_text="[A] Apply",
                image_path=None,
                image_path_selected=None,
                description="Bright & vivid: 60/55/55",
                icon=None,
                value=lambda input: self.apply_preset(input, "vivid")
            )
        )

        return option_list
