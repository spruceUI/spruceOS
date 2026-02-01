import ctypes
import fcntl
import math
from pathlib import Path
import re
import subprocess
import time
from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from devices.bluetooth.bluetooth_scanner import BluetoothScanner
from devices.charge.charge_status import ChargeStatus
import os
from devices.device_common import DeviceCommon
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from display.display import Display
from games.utils.device_specific.miyoo_trim_game_system_utils import MiyooTrimGameSystemUtils
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from menus.settings.button_remapper import ButtonRemapper
from menus.settings.timezone_menu import TimezoneMenu
from utils import throttle
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class TrimUIDevice(DeviceCommon):
    
    def __init__(self):
        self.button_remapper = ButtonRemapper(self.system_config)
        self.game_utils = MiyooTrimGameSystemUtils()

    def on_system_config_changed(self):
        old_volume = self.system_config.get_volume()
        self.system_config.reload_config()
        new_volume = self.system_config.get_volume()
        if(old_volume != new_volume):
            Display.volume_changed(new_volume)

    def ensure_wpa_supplicant_conf(self):
        MiyooTrimCommon.ensure_wpa_supplicant_conf(self.get_wpa_supplicant_conf_path())
        
    def clear_framebuffer(self):
        pass

    def capture_framebuffer(self):
        pass

    def restore_framebuffer(self):
        pass
    

    def power_off_cmd(self):
        return "poweroff"
    

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

    def run_cmd(self, args, dir = None):
        MiyooTrimCommon.run_cmd(self, args, dir)
        
    def run_app(self, folder,launch):
        MiyooTrimCommon.run_app(self, folder,launch)

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
        return self.system_config.is_bluetooth_enabled()
    
    
    def disable_bluetooth(self):
        PyUiLogger.get_logger().info(f"Disabling Bluetooth")
        ProcessRunner.run(["killall","-15","bluetoothd"])
        time.sleep(0.1)  
        ProcessRunner.run(["killall","-9","bluetoothd"])
        self.system_config.set_bluetooth(0)

    def perform_startup_tasks(self):
        pass

    def get_bluetooth_scanner(self):
        return BluetoothScanner()

    def get_favorites_path(self):
        return "/mnt/SDCARD/Saves/pyui-favorites.json"
        
    def get_recents_path(self):
        return "/mnt/SDCARD/Saves/pyui-recents.json"
            
    def get_apps_config_path(self):
        return "/mnt/SDCARD/Saves/pyui-apps.json"

    def get_collections_path(self):
        return "/mnt/SDCARD/Collections/"

    def get_state_path(self):
        return "/mnt/SDCARD/Saves/pyui-state.json"

    def launch_stock_os_menu(self):
        pass

    def calibrate_sticks(self):
        pass

    def supports_analog_calibration(self):
        return False

    def supports_image_resizing(self):
        return True

    def remap_buttons(self):
        self.button_remapper.remap_buttons()

    def supports_wifi(self):
        return True
    
    def get_game_system_utils(self):
        return self.game_utils
    
    def get_roms_dir(self):
        return "/mnt/SDCARD/Roms/"

    def take_snapshot(self, path):
        return None
    
    def get_wpa_supplicant_conf_path(self):
        return PyUiConfig.get_wpa_supplicant_conf_file_location("/userdata/cfg/wpa_supplicant.conf")
    
    def supports_brightness_calibration():
        return True

    def supports_contrast_calibration():
        return True

    def supports_saturation_calibration():
        return True

    def supports_hue_calibration():
        return True

    def get_save_state_image(self, rom_info: RomInfo):
        return self.get_game_system_utils().get_save_state_image(rom_info)

    def get_fw_version(self):
        try:
            with open(f"/etc/version") as f:
                return f.read().strip()
        except Exception as e:
            PyUiLogger.get_logger().error(f"Could not read FW version : {e}")
            return "Unknown"

    def get_core_for_game(self, game_system_config, rom_file_path):
        core = game_system_config.get_effective_menu_selection("Emulator", rom_file_path)
        if(core is None):
            core = game_system_config.get_effective_menu_selection("Emulator_64", rom_file_path)
        return core
    
    def supports_timezone_setting(self):
        return True

    def prompt_timezone_update(self):
        timezone_menu = TimezoneMenu()
        tz = timezone_menu.ask_user_for_timezone(timezone_menu.list_timezone_files('/usr/share/zoneinfo', verify_via_datetime=True))

        if (tz is not None):
            self.system_config.set_timezone(tz)
            self.apply_timezone(tz)

    def apply_timezone(self, timezone):
        """
        timezone example: "America/New_York"
        """

        zoneinfo_path = Path("/usr/share/zoneinfo") / timezone
        localtime_path = Path("/etc/localtime")

        if not zoneinfo_path.exists():
            raise ValueError(f"Invalid timezone: {timezone}")

        # Update system timezone symlink 
        try:
            subprocess.run(
                ["ln", "-sf", str(zoneinfo_path), str(localtime_path)],
                check=True
            )
        except Exception as e:
            PyUiLogger.get_logger.error(f"Failed to update /etc/localtime: {e}")

        # Update environment for current process
        os.environ["TZ"] = timezone
        time.tzset()
        self.sync_hw_clock()
