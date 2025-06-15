import ctypes
import fcntl
import math
import re
import subprocess
from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from devices.charge.charge_status import ChargeStatus
import os
from devices.device_common import DeviceCommon
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from games.utils.game_entry import GameEntry
from menus.settings.button_remapper import ButtonRemapper
from utils import throttle
from utils.logger import PyUiLogger

class TrimUIDevice(DeviceCommon):
    
    def __init__(self):
        self.button_remapper = ButtonRemapper(self.system_config)

    def ensure_wpa_supplicant_conf(self):
        MiyooTrimCommon.ensure_wpa_supplicant_conf()

    @property
    def power_off_cmd(self):
        return "poweroff"
    
    @property
    def reboot_cmd(self):
        return "reboot"
        
    def _set_lumination_to_config(self):
        val = self.map_backlight_from_10_to_full_255(self.system_config.backlight)
        try:
            DISP_LCD_SET_BRIGHTNESS = 0x102 
            fd = os.open("/dev/disp", os.O_RDWR)
            if fd > 0:
                # Create a ctypes array equivalent to: unsigned long param[4] = {0, val, 0, 0};
                param = (ctypes.c_ulong * 4)(0, val, 0, 0)
                # Perform ioctl with pointer to param
                fcntl.ioctl(fd, DISP_LCD_SET_BRIGHTNESS, param)
                os.close(fd)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error setting brightness: {e}")

    def _set_contrast_to_config(self):
        with open("/sys/devices/virtual/disp/disp/attr/enhance_contrast", "w") as f:
            f.write(str(self.system_config.contrast * 5))

    def _set_saturation_to_config(self):
        with open("/sys/devices/virtual/disp/disp/attr/enhance_saturation", "w") as f:
            f.write(str(self.system_config.saturation * 5))

    def _set_brightness_to_config(self):
        with open("/sys/devices/virtual/disp/disp/attr/enhance_bright", "w") as f:
            f.write(str(self.system_config.brightness * 5))

    def _set_hue_to_config(self):
        with open("/sys/devices/virtual/disp/disp/attr/color_temperature", "w") as f:
            f.write(str((self.system_config.hue * 5) - 50))
            
    def _set_volume(self, user_volume):
        from display.display import Display
        if(user_volume < 0):
            user_volume = 0
        elif(user_volume > 100):
            user_volume = 100
        volume = math.ceil(user_volume * 255//100)
        
        try:
            
            ProcessRunner.run(
                ["amixer", "cset", f"numid=17", str(int(volume))],
                check=True
            )

        except subprocess.CalledProcessError as e:
            PyUiLogger.get_logger().error(f"Failed to set volume: {e}")

        self.system_config.reload_config()
        self.system_config.set_volume(user_volume)
        self.system_config.save_config()
        Display.volume_changed(user_volume)
        return user_volume

    def get_volume(self):
        return self.system_config.get_volume()

    def get_real_volume(self):
        # Run the command and capture output
        result = subprocess.run(['amixer', 'cget', 'numid=17'], capture_output=True, text=True)
        # Search for 'values=' line and extract the first value
        match = re.search(r'values=(\d+),\d+', result.stdout)
        if match:
            volume = int(match.group(1))
            PyUiLogger().get_logger().info(f"Volume is {volume}")
            return math.ceil(volume * 100/255)
        else:
            PyUiLogger().get_logger().error("Unable to find volume from amixer command")
            return 0
        
    def fix_sleep_sound_bug(self):
        pass

    def sleep(self):
        try:
            with open("/sys/power/state", "w") as f:
                f.write("mem")  
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failure attempting to sleep: {e}")


    def run_game(self, rom_info):
        return MiyooTrimCommon.run_game(self, rom_info)

    def run_app(self, args, dir = None):
        MiyooTrimCommon.run_app(self, args, dir)

    def map_digital_input(self, sdl_input):
        mapping = self.sdl_button_to_input.get(sdl_input, ControllerInput.UNKNOWN)
        if(ControllerInput.UNKNOWN == mapping):
            PyUiLogger.get_logger().error(f"Unknown input {sdl_input}")
        return self.button_remapper.get_mappping(mapping)
    
    def map_key(self, key_code):
        if(116 == key_code):
            return self.button_remapper.get_mappping(ControllerInput.POWER_BUTTON)
        if(115 == key_code):
            return self.button_remapper.get_mappping(ControllerInput.VOLUME_UP)
        elif(114 == key_code):
            return self.button_remapper.get_mappping(ControllerInput.VOLUME_DOWN)
        else:
            PyUiLogger.get_logger().debug(f"Unrecognized keycode {key_code}")
            return None

    
    def special_input(self, controller_input, length_in_seconds):
        if(ControllerInput.POWER_BUTTON == controller_input):
            if(length_in_seconds < 1):
                self.sleep()
            else:
                self.prompt_power_down()
        elif(ControllerInput.VOLUME_UP == controller_input):
            self.change_volume(+5)
        elif(ControllerInput.VOLUME_DOWN == controller_input):
            self.change_volume(-5)

    def map_analog_input(self, sdl_axis, sdl_value):
        PyUiLogger.get_logger().error(f"Received analog input axis = {sdl_axis}, value = {sdl_value}")

    def get_wifi_connection_quality_info(self) -> WiFiConnectionQualityInfo:
        try:
            result = subprocess.run(
                ["iw", "dev", "wlan0", "link"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            output = result.stdout.strip()

            if "Not connected." in output or result.returncode != 0:
                return WiFiConnectionQualityInfo(noise_level=0, signal_level=0, link_quality=0)

            signal_level = 0
            link_quality = 0  # This won't be available directly via iw, unless you derive it

            # Extract signal level (in dBm)
            signal_match = re.search(r"signal:\s*(-?\d+)\s*dBm", output)
            if signal_match:
                signal_level = int(signal_match.group(1))

            # Optional: derive link quality heuristically (e.g., map signal strength to 0–70 or 0–100)
            # Example rough mapping:
            if signal_level <= -100:
                link_quality = 0
            elif signal_level >= -50:
                link_quality = 70
            else:
                link_quality = int((signal_level + 100) * 1.4)  # Maps -100..-50 dBm to 0..70

            return WiFiConnectionQualityInfo(
                noise_level=0,  # Not available via `iw`
                signal_level=signal_level,
                link_quality=link_quality
            )

        except Exception as e:
            PyUiLogger.get_logger().error(f"An error occurred {e}")
            return WiFiConnectionQualityInfo(noise_level=0, signal_level=0, link_quality=0)
             
    def set_wifi_power(self, value):
        pass

    def stop_wifi_services(self):
        MiyooTrimCommon.stop_wifi_services(self)

    def start_wpa_supplicant(self):
        MiyooTrimCommon.start_wpa_supplicant(self)

    def is_wifi_enabled(self):
        return self.system_config.is_wifi_enabled()

    def disable_wifi(self):
        MiyooTrimCommon.disable_wifi(self)

    def enable_wifi(self):
        MiyooTrimCommon.enable_wifi(self)

    @throttle.limit_refresh(5)
    def get_charge_status(self):
        #Probably need to find the power and not just usb
        with open("/sys/class/power_supply/axp2202-usb/online", "r") as f:
            ac_online = int(f.read().strip())
            
        if(ac_online):
           return ChargeStatus.CHARGING
        else:
            return ChargeStatus.DISCONNECTED
    
    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        with open("/sys/class/power_supply/axp2202-battery/capacity", "r") as f:
            return int(f.read().strip()) 
        return 0
        
    def get_app_finder(self):
        return MiyooAppFinder()
    
    def parse_favorites(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_favorites()
    
    def parse_recents(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_recents()

    def is_bluetooth_enabled(self):
        return False
    
    
    def disable_bluetooth(self):
        pass

    def enable_bluetooth(self):
        pass

    def perform_startup_tasks(self):
        pass

    def get_bluetooth_scanner(self):
        return None

    def get_favorites_path(self):
        return "/mnt/SDCARD/Saves/pyui-favorites.json"
        
    def get_recents_path(self):
        return "/mnt/SDCARD/Saves/pyui-recents.json"
    
    def get_state_path(self):
        return "/mnt/SDCARD/Saves/pyui-state.json"

    def launch_stock_os_menu(self):
        pass

    def calibrate_sticks(self):
        pass

    def supports_analog_calibration(self):
        return False

    def remap_buttons(self):
        self.button_remapper.remap_buttons()