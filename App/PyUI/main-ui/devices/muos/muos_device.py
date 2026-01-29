import json
from pathlib import Path
import shutil
import subprocess
import sys
from apps.muos.muos_app_finder import MuosAppFinder
from controller.controller_inputs import ControllerInput
from devices.charge.charge_status import ChargeStatus
import os
from devices.device_common import DeviceCommon
from devices.miyoo.system_config import SystemConfig
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from games.utils.device_specific.muos_game_system_utils import MuosGameSystemUtils
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from menus.settings.button_remapper import ButtonRemapper
from utils import throttle
from utils.config_copier import ConfigCopier
from utils.logger import PyUiLogger

from devices.device_common import DeviceCommon
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

class MuosDevice(DeviceCommon):
    def __init__(self):
        self.button_remapper = ButtonRemapper(self.system_config)
        self.muos_systems = self.load_assign_json()

    def setup_system_config(self):
        base_dir = os.path.abspath(sys.path[0])
        PyUiLogger.get_logger().info(f"base_dir is {base_dir}")
        self.script_dir = os.path.join(base_dir, "devices","muos")
        self.parent_dir = os.path.dirname(base_dir)
        source = os.path.join(self.script_dir,"muos-system.json") 
        system_json_path = os.path.join(self.parent_dir,"muos-system.json")
        self._load_system_config(system_json_path, Path(source))

    def sleep(self):
        ProcessRunner.run(["/opt/muos/script/system/suspend.sh"])

    def ensure_wpa_supplicant_conf(self):
        pass

    def should_scale_screen(self):
        return self.is_hdmi_connected()

    
    def power_off_cmd(self):
        return "poweroff"
    
    
    def reboot_cmd(self):
        return "reboot"

    # Why does this break? Using the script should be better than just
    # Running the direct command
    #def power_off(self):
    #    ProcessRunner.run(["/opt/muos/script/system/halt.sh", "poweroff"])
    #def reboot(self):
    #    ProcessRunner.run(["/opt/muos/script/system/halt.sh", "reboot"])



    def _set_volume(self, volume):
        ProcessRunner.run(["/opt/muos/script/device/audio.sh", str(volume)])
        return volume 


    def _set_brightness_to_config(self):
        pass

    def _set_lumination_to_config(self):
        luminosity = self.map_backlight_from_10_to_full_255(self.system_config.backlight)
        ProcessRunner.run(["/opt/muos/script/device/bright.sh", str(luminosity)])
    
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

    def run_cmd(self, args, dir = None):
        PyUiLogger.get_logger().debug(f"About to launch app {args} from dir {dir}")
        subprocess.run(args, cwd = dir)
    
    def run_app(self, folder,launch):
        directory = os.path.dirname(launch)
        PyUiLogger.get_logger().debug(f"About to launch app {launch} from dir {directory}")
        subprocess.run([launch], cwd = directory)

    
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
        return os.path.join(self.parent_dir,"/pyui-favorites.json")
    
    def get_recents_path(self):
        return os.path.join(self.parent_dir,"/pyui-recents.json")
            
    def get_apps_config_path(self):
        return os.path.join(self.parent_dir,"/pyui-apps.json")

    def get_collections_path(self):
        return os.path.join(self.parent_dir,"/Collections/")

    def launch_stock_os_menu(self):
        os._exit(0)

    def get_state_path(self):
        return os.path.join(self.parent_dir,"/pyui-state.json")

    def calibrate_sticks(self):
        pass

    def supports_analog_calibration(self):
        return False
    
    def supports_image_resizing(self):
        return True

    def remap_buttons(self):
        self.button_remapper.remap_buttons()

    def supports_wifi(self):
        return False #Let it be handled in muOS proper, too lazy to implement
    
    def get_roms_dir(self):
        return "/mnt/union/ROMS/"
    
    
    def screen_width(self):
        return  int(self.read_based_on_muos_config("/opt/muos/device/config/screen/internal/width"))

    
    def screen_height(self):
        return int(self.read_based_on_muos_config("/opt/muos/device/config/screen/internal/height"))
    
    
    def screen_rotation(self):
        return int(self.read_based_on_muos_config("/opt/muos/device/config/screen/rotate"))

    
    def output_screen_width(self):
        if(self.should_scale_screen()):
            return 1920
        else:
            return self.screen_width()
        
    
    def output_screen_height(self):
        if(self.should_scale_screen()):
            return 1080
        else:
            return self.screen_height()

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
        assign_path = "/opt/muos/share/info/assign/assign.json"
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

    def add_app_launch_as_startup(self, input):
        from display.display import Display
        if (ControllerInput.A == input):
            muos_frontend_sh_path = "/opt/muos/script/mux/frontend.sh"        
            updated_frontend = os.path.join(self.script_dir,"frontend.sh") 
            
            try:
                shutil.copyfile(updated_frontend, muos_frontend_sh_path)
                PyUiLogger.get_logger().info(f"Copied {updated_frontend} to {muos_frontend_sh_path}")
            except OSError as e:
                PyUiLogger.get_logger().warning(f"Failed to copy file: {e}")
                
            startup_path = "/opt/muos/config/settings/general/startup"
            try:
                with open(startup_path, "w") as f:
                    f.write("lastapp\n")
                
                Display.display_message("Last muOS launched App will launch on startup",2000)
            except OSError as e:
                PyUiLogger.get_logger().warning(f"Failed to write to {startup_path}: {e}")
                Display.display_message("Error updating startup script",2000)


    def get_extra_settings_options(self):
        option_list = []
        option_list.append(
                GridOrListEntry(
                        primary_text=Language.set_pyui_as_startup(),
                        value_text=None,
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.add_app_launch_as_startup
                    )
                )
        return option_list

    def take_snapshot(self, path):
        return None
    
    def get_save_state_image(self, rom_info: RomInfo):
        #TODO, where does it store this?
        return None

    def get_wpa_supplicant_conf_path(self):
        return None

    def supports_brightness_calibration(self):
        return False

    def supports_contrast_calibration(self):
        return False

    def supports_saturation_calibration(self):
        return False

    def supports_hue_calibration(self):
        return False

    def supports_qoi(self):
        return False

    def keep_running_on_error(self):
        return False

    def perform_sdcard_ro_check(self):
        PyUiLogger.get_logger().info("MUOS Device does not check for read-only SD card status.")