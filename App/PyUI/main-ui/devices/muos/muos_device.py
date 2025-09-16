import json
import re
import subprocess
import time
from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from apps.muos.muos_app_finder import MuosAppFinder
from controller.controller_inputs import ControllerInput
from controller.key_watcher_controller import KeyWatcherController
from devices.bluetooth.bluetooth_scanner import BluetoothScanner
from devices.charge.charge_status import ChargeStatus
import os
from devices.device_common import DeviceCommon
from devices.miyoo.trim_ui_joystick import TrimUIJoystick
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from games.utils.device_specific.muos_game_system_utils import MuosGameSystemUtils
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from menus.settings.button_remapper import ButtonRemapper
import sdl2
from utils import throttle
from utils.logger import PyUiLogger

from devices.device_common import DeviceCommon


class MuosDevice(DeviceCommon):
    OUTPUT_MIXER = 2
    SOUND_DISABLED = 0

    def __init__(self):
        self.button_remapper = ButtonRemapper(self.system_config)
        self.muos_systems = self.load_assign_json()

    def sleep(self):
        ProcessRunner.run(["/opt/muos/script/system/suspend.sh"])

    def ensure_wpa_supplicant_conf(self):
        pass

    def should_scale_screen(self):
        return self.is_hdmi_connected()

    @property
    def power_off_cmd(self):
        return "poweroff"
    
    @property
    def reboot_cmd(self):
        return "reboot"

    def _set_volume(self, volume):
        ProcessRunner.run(["/opt/muos/device/script/audio.sh", str(volume)])
        return volume 


    def _set_brightness_to_config(self):
        pass

    def _set_lumination_to_config(self):
        luminosity = self.map_backlight_from_10_to_full_255(self.system_config.backlight)
        ProcessRunner.run(["/opt/muos/device/script/bright.sh", str(luminosity)])
    
    def _set_contrast_to_config(self):
        pass
    
    def _set_saturation_to_config(self): 
        pass


    def _set_hue_to_config(self):
        # echo val > /sys/class/disp/disp/attr/color_temperature
        pass

    def get_volume(self):
        return self.system_config.get_volume()

    def read_volume(self):
        return self.system_config.get_volume()

    def run_game(self, rom_info: RomInfo) -> subprocess.Popen:
        launch_path = os.path.join(rom_info.game_system.game_system_config.get_emu_folder(),rom_info.game_system.game_system_config.get_launch())
        PyUiLogger.get_logger().info(f"About to launch {launch_path} with rom {rom_info.rom_file_path}")
        return subprocess.Popen([launch_path,rom_info.rom_file_path], stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def run_app(self, args, dir = None):
        PyUiLogger.get_logger().debug(f"About to launch app {args} from dir {dir}")
        subprocess.run(args, cwd = dir)
    
    def map_digital_input(self, sdl_input):
        return None

    def map_analog_input(self, sdl_axis, sdl_value):
        return None

    def prompt_power_down(self):
        DeviceCommon.prompt_power_down(self)

    def special_input(self, controller_input, length_in_seconds):
        if(ControllerInput.POWER_BUTTON == controller_input):
            if(length_in_seconds < 1):
                self.sleep()
            else:
                self.prompt_power_down()
        elif(ControllerInput.VOLUME_UP == controller_input):
            self.change_volume(5)
        elif(ControllerInput.VOLUME_DOWN == controller_input):
            self.change_volume(-5)

    def get_wifi_connection_quality_info(self) -> WiFiConnectionQualityInfo:
        return WiFiConnectionQualityInfo(noise_level=0, signal_level=0, link_quality=0)


    def set_wifi_power(self, value):
        pass

    def stop_wifi_services(self):
        pass

    def start_wpa_supplicant(self):
        pass

    def is_wifi_enabled(self):
        return self.system_config.is_wifi_enabled()

    def disable_wifi(self):
        pass

    def enable_wifi(self):
        pass

    def execute_based_on_muos_config(self, file_path):
        try:
            # Read the command from the file
            with open(file_path, "r") as f:
                location = f.read().strip()

            # Read the value
            with open(location, "r") as f:
                return int(f.read().strip())

        except Exception as e:
            PyUiLogger.get_logger().error(f"Error executing to get value from {file_path} so returning 0s : {e}")
        
        return 0

    def read_based_on_muos_config(self, file_path):
        try:
            # Read the command from the file
            with open(file_path, "r") as f:
                return f.read().strip()
            
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error reading value from {file_path} so returning 0s : {e}")
        
        return 0


    @throttle.limit_refresh(5)
    def get_charge_status(self):
        try:
            ac_online = self.execute_based_on_muos_config("/opt/muos/device/config/battery/charger")
            if(ac_online):
                return ChargeStatus.CHARGING
            else:
                return ChargeStatus.DISCONNECTED
                
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error reading battery percentage : {e}")
        
        return ChargeStatus.DISCONNECTED
    
    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        return self.execute_based_on_muos_config("/opt/muos/device/config/battery/capacity")

    def get_app_finder(self):
        return MuosAppFinder()
    
    def parse_favorites(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_favorites()
    
    def parse_recents(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_recents()

    def is_bluetooth_enabled(self):
        return False #Let it be handled in muOS proper, too lazy to implement
    
    def disable_bluetooth(self):
        pass

    def enable_bluetooth(self):
        pass
            
    def perform_startup_tasks(self):
        pass

    def get_bluetooth_scanner(self):
        return None

    def get_favorites_path(self):
        return "/mnt/sdcard/Saves/pyui-favorites.json"
    
    def get_recents_path(self):
        return "/mnt/sdcard/Saves/pyui-recents.json"
    
    def get_collections_path(self):
        return "/mnt/sdcard/Collections/"

    def launch_stock_os_menu(self):
        os._exit(0)

    def get_state_path(self):
        return "/mnt/sdcard/Saves/pyui-state.json"

    def calibrate_sticks(self):
        from controller.controller import Controller

    def supports_analog_calibration(self):
        return False
    
    def remap_buttons(self):
        self.button_remapper.remap_buttons()

    def supports_wifi(self):
        return False #Let it be handled in muOS proper, too lazy to implement
    
    def get_roms_dir(self):
        return "/mnt/union/ROMS/"
    
    @property
    def screen_width(self):
        return  int(self.read_based_on_muos_config("/opt/muos/device/config/screen/internal/width"))

    @property
    def screen_height(self):
        return int(self.read_based_on_muos_config("/opt/muos/device/config/screen/internal/height"))
    
    @property
    def screen_rotation(self):
        return int(self.read_based_on_muos_config("/opt/muos/device/config/screen/rotate"))

    @property
    def output_screen_width(self):
        if(self.should_scale_screen()):
            return 1920
        else:
            return self.screen_width
        
    @property
    def output_screen_height(self):
        if(self.should_scale_screen()):
            return 1080
        else:
            return self.screen_height

    def get_scale_factor(self):
        if(self.is_hdmi_connected()):
            return 2.25
        else:
            return 1
        
    def get_game_system_utils(self):
        return MuosGameSystemUtils(self.muos_systems)
    
    
    def load_assign_json(self, uppercase_keys: bool = True) -> dict:
        """
        Loads the assign.json file from MUOS info path.
        If uppercase_keys is True, all keys are converted to uppercase.
        """
        assign_path = "/mnt/mmc/MUOS/info/assign/assign.json"
        try:
            with open(assign_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except FileNotFoundError:
            PyUiLogger.get_logger().error(f"{assign_path} not found")
            return {}
        except json.JSONDecodeError as e:
            PyUiLogger.get_logger().error(f"Error decoding JSON from {assign_path}: {e}")
            return {}

        if uppercase_keys:
            return {k.upper(): v for k, v in data.items()}

        return data

    