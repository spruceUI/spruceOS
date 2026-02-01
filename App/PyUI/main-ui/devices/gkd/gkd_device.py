import re
import socket
import subprocess
from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from controller.sdl.sdl2_controller_interface import Sdl2ControllerInterface
from devices.charge.charge_status import ChargeStatus
from devices.device_common import DeviceCommon
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from display.display import Display
from games.utils.device_specific.miyoo_trim_game_system_utils import MiyooTrimGameSystemUtils
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from menus.settings.button_remapper import ButtonRemapper
from utils import throttle
from utils.logger import PyUiLogger

class GKDDevice(DeviceCommon):
    
    def __init__(self):
        self.button_remapper = ButtonRemapper(self.system_config)
        self.game_utils = MiyooTrimGameSystemUtils()
        self.sdl2_controller_interface = Sdl2ControllerInterface()

    def on_system_config_changed(self):
        old_volume = self.system_config.get_volume()
        self.system_config.reload_config()
        new_volume = self.system_config.get_volume()
        if(old_volume != new_volume):
            Display.volume_changed(new_volume)

    def get_controller_interface(self):
        return self.sdl2_controller_interface


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
        with open("/sys/class/backlight/backlight/brightness", "w") as f:
            f.write(str(self.map_backlight_from_10_to_full_255(self.system_config.backlight)))

    def _set_contrast_to_config(self):
        ProcessRunner.run(["modetest", "-M", "rockchip", "-a", "-w", 
                                     "179:contrast:"+str(self.system_config.contrast * 5)])
    
    def _set_saturation_to_config(self):
        ProcessRunner.run(["modetest", "-M", "rockchip", "-a", "-w", 
                                     "179:saturation:"+str(self.system_config.saturation * 5)])

    def _set_brightness_to_config(self):
        ProcessRunner.run(["modetest", "-M", "rockchip", "-a", "-w", 
                                     "179:brightness:"+str(self.system_config.brightness * 5)])

    def _set_hue_to_config(self):
        ProcessRunner.run(["modetest", "-M", "rockchip", "-a", "-w", 
                                     "179:hue:"+str(self.system_config.hue * 5)])

    def get_volume(self):
        return self.system_config.get_volume()

    def get_real_volume(self):
        # Run the command and capture output
        result = subprocess.run(['pactl', 'get-sink-volume', '@DEFAULT_SINK@'], capture_output=True, text=True)
        # Search for 'values=' line and extract the first value
        match = re.search(r'(\d?\d+?)%', result.stdout)
        if match:
            volume = int(match.group(1))
            PyUiLogger().get_logger().info(f"Volume is {volume}")
            return volume
        else:
            PyUiLogger().get_logger().error("Unable to find volume from pactl command")
            return 0
        
    def fix_sleep_sound_bug(self):
        pass

    def sleep(self):
        # system handles this, not sure if implementing
        pass


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
        elif(115 == key_code):
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
            with open("/proc/net/wireless", "r") as f:
                output = f.read().strip().splitlines()

            if len(output) >= 3:
                # The 3rd line contains the actual wireless stats
                data_line = output[2]
                parts = data_line.split()

                # According to the standard format:
                # parts[2] = link quality (float ending in '.')
                # parts[3] = signal level
                # parts[4] = noise level
                link_quality = int(float(parts[2].strip('.')))
                signal_level = int(float(parts[3].strip('.')))
                noise_level = int(float(parts[4].strip('.')))

                return WiFiConnectionQualityInfo(
                    noise_level=noise_level,
                    signal_level=signal_level,
                    link_quality=link_quality
                )
            else:
                return WiFiConnectionQualityInfo(noise_level=0, signal_level=0, link_quality=0)

        except Exception as e:
            PyUiLogger.get_logger().error(f"An error occurred {e}")
            return WiFiConnectionQualityInfo(noise_level=0, signal_level=0, link_quality=0)

    def get_wpa_supplicant_conf_path(self):
        return None

    def start_wifi_services(self):
        pass

    def stop_wifi_services(self):
        pass

    def is_wifi_enabled(self):
        return self.system_config.is_wifi_enabled()

    @throttle.limit_refresh(10)
    def get_ip_addr_text(self):
        import psutil
        if self.is_wifi_enabled():
            if not self.get_wifi_menu().adapter_is_connected():
                return "No USB adapter"

            try:
                addrs = psutil.net_if_addrs().get("wlan0")
                if addrs:
                    for addr in addrs:
                        if addr.family == socket.AF_INET:
                            return addr.address
                    return "Connecting"
                else:
                    return "Connecting"
            except Exception:
                return "Error"

        return "Off"

    def disable_wifi(self):
        self.system_config.reload_config()
        self.system_config.set_wifi(0)
        self.system_config.save_config()
        ProcessRunner.run(["connmanctl", "disable", "wifi"])
        self.get_wifi_status.force_refresh()
        self.get_ip_addr_text.force_refresh()

    def enable_wifi(self):
        self.system_config.reload_config()
        self.system_config.set_wifi(1)
        self.system_config.save_config()
        ProcessRunner.run(["systemctl", "restart", "connman"])
        ProcessRunner.run(["connmanctl", "enable", "wifi"])
        self.get_wifi_status.force_refresh()
        self.get_ip_addr_text.force_refresh()

    @throttle.limit_refresh(5)
    def get_charge_status(self):
        #Probably need to find the power and not just usb
        with open("/sys/class/power_supply/usb/online", "r") as f:
            ac_online = int(f.read().strip())
            
        if(ac_online):
           return ChargeStatus.CHARGING
        else:
            return ChargeStatus.DISCONNECTED
    
    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        with open("/sys/class/power_supply/battery/capacity", "r") as f:
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
