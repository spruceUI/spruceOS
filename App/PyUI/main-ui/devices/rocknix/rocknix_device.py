import json
import subprocess
from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from devices.charge.charge_status import ChargeStatus
import os
from devices.device_common import DeviceCommon
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from display.display import Display
from games.utils.device_specific.miyoo_trim_game_system_utils import MiyooTrimGameSystemUtils
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from menus.settings.button_remapper import ButtonRemapper
from utils import throttle
from utils.logger import PyUiLogger

from devices.device_common import DeviceCommon


class RocknixDevice(DeviceCommon):
    def __init__(self):
        self.button_remapper = ButtonRemapper(self.system_config)
        self.muos_systems = self.load_assign_json()
        self.game_utils = MiyooTrimGameSystemUtils(roms_path="/storage/roms/",emu_path="/storage/Emu")

    def sleep(self):
        pass

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

    def _set_brightness_to_config(self):
        pass

    def _set_lumination_to_config(self):
        pass

    def _set_contrast_to_config(self):
        pass
    
    def _set_saturation_to_config(self): 
        pass


    def _set_hue_to_config(self):
        pass

    def get_volume(self):
        return self.system_config.get_volume()

    def run_game(self, rom_info: RomInfo) -> subprocess.Popen:
        from controller.controller import Controller
        menu_options = rom_info.game_system.game_system_config.get_menu_options()
        selected_core = self.get_selected_emulator(menu_options, self.device_name)
        if(selected_core is None):
            Display.display_message("No core found", 2_000)
            return

        selected_core = "/storage/RetroArch/.retroarch/cores64/" + selected_core + "_libretro.so"

        #shutil.copyfile("/mnt/SDCARD/RetroArch/platform/retroarch-AnbernicRG_XX-universal.cfg", "/mnt/SDCARD/RetroArch/retroarch.cfg")
        cmds = [
                "/usr/bin/retroarch",
                "-v",
                "--config", "/storage/.config/retroarch/retroarch.cfg",
                "--log-file","/storage/Saves/spruce/retroarch.log",
                "-L",selected_core,
                rom_info.rom_file_path]

        directory = "/storage/RetroArch/"
        PyUiLogger.get_logger().debug(f"About to launch {cmds} from dir {directory}")
        Display.deinit_display()
        subprocess.run(cmds, cwd = directory)
        Display.init()

        Controller.clear_input_queue()

    def run_cmd(self, args, dir = None, is_power_cmd = False):
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

    def _set_volume(self, volume):
        return volume 
    
    def change_volume(self, amount):
        from display.display import Display
        self.system_config.reload_config()
        volume = self.get_volume() + amount
        if(volume < 0):
            volume = 0
        elif(volume > 100):
            volume = 100
        self._set_volume(volume)
        self.system_config.set_volume(volume)
        self.system_config.save_config()
        Display.volume_changed(self.get_volume())

    def volume_up(self):
        self.change_volume(+5)
    
    def volume_down(self):
        self.change_volume(-5)

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

    @throttle.limit_refresh(5)
    def get_charge_status(self):
        return ChargeStatus.DISCONNECTED
    
    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        return 0

    def get_app_finder(self):
        return MiyooAppFinder(app_dir="/storage/App")
    
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
        return "/storage/pyui/config/pyui-favorites.json"
    
    def get_recents_path(self):
        return "/storage/pyui/config/pyui-recents.json"
            
    def get_apps_config_path(self):
        return "/storage/pyui/config/pyui-apps.json"

    def get_collections_path(self):
        return "/storage/pyui/config/storage/collections/"

    def launch_stock_os_menu(self):
        os._exit(0)

    def get_state_path(self):
        return "/storage/pyui/config/pyui-state.json"

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
        return self.game_utils
    
    
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

    def get_extra_settings_options(self):
        option_list = []
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
        PyUiLogger.get_logger().info("Rocknix Device does not check for read-only SD card status.")