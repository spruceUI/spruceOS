import subprocess
import time
from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from devices.device_common import DeviceCommon
from devices.miyoo.trim_ui_joystick import TrimUIJoystick
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from games.utils.device_specific.miyoo_trim_game_system_utils import MiyooTrimGameSystemUtils
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from menus.settings.button_remapper import ButtonRemapper
import sdl2
from utils.logger import PyUiLogger

from devices.device_common import DeviceCommon


class MiyooDevice(DeviceCommon):
    OUTPUT_MIXER = 2
    SOUND_DISABLED = 0

    def __init__(self):
        self.button_remapper = ButtonRemapper(self.system_config)
        self.game_utils = MiyooTrimGameSystemUtils()

    def clear_framebuffer(self):
        pass
    
    def capture_framebuffer(self):
        pass

    def restore_framebuffer(self):
        pass

    def sleep(self):
        with open("/sys/power/mem_sleep", "w") as f:
            f.write("deep")
        with open("/sys/power/state", "w") as f:
            f.write("mem")  

    def ensure_wpa_supplicant_conf(self):
        MiyooTrimCommon.ensure_wpa_supplicant_conf(self.get_wpa_supplicant_conf_path())

    def should_scale_screen(self):
        return self.is_hdmi_connected()


    def run_cmd(self, args, dir = None):
        MiyooTrimCommon.run_cmd(self, args, dir)

    def run_app(self, folder,launch):
        MiyooTrimCommon.run_app(self, folder,launch)

    #TODO untested
    def map_analog_axis(self,sdl_input, value, threshold=16000):
        if sdl_input == sdl2.SDL_CONTROLLER_AXIS_LEFTX:
            if value < -threshold:
                return ControllerInput.LEFT_STICK_LEFT
            elif value > threshold:
                return ControllerInput.LEFT_STICK_RIGHT
        elif sdl_input == sdl2.SDL_CONTROLLER_AXIS_LEFTY:
            if value < -threshold:
                return ControllerInput.LEFT_STICK_UP
            elif value > threshold:
                return ControllerInput.LEFT_STICK_DOWN
        elif sdl_input == sdl2.SDL_CONTROLLER_AXIS_RIGHTX:
            if value < -threshold:
                return ControllerInput.RIGHT_STICK_LEFT
            elif value > threshold:
                return ControllerInput.RIGHT_STICK_RIGHT
        elif sdl_input == sdl2.SDL_CONTROLLER_AXIS_RIGHTY:
            if value < -threshold:
                return ControllerInput.RIGHT_STICK_UP
            elif value > threshold:
                return ControllerInput.RIGHT_STICK_DOWN
        return None
    
    def map_digital_input(self, sdl_input):
        mapping = self.sdl_button_to_input.get(sdl_input, ControllerInput.UNKNOWN)
        if(ControllerInput.UNKNOWN == mapping):
            PyUiLogger.get_logger().error(f"Unknown input {sdl_input}")
        return self.button_remapper.get_mappping(mapping)

    def map_analog_input(self, sdl_axis, sdl_value):
        if sdl_axis == 5 and sdl_value == 32767:
            return self.button_remapper.get_mappping(ControllerInput.R2)
        elif sdl_axis == 4 and sdl_value == 32767:
            return self.button_remapper.get_mappping(ControllerInput.L2)
        else:
            # Update min/max range
            if sdl_axis not in self.unknown_axis_ranges:
                self.unknown_axis_ranges[sdl_axis] = (sdl_value, sdl_value)
            else:
                current_min, current_max = self.unknown_axis_ranges[sdl_axis]
                self.unknown_axis_ranges[sdl_axis] = (
                    min(current_min, sdl_value),
                    max(current_max, sdl_value)
                )

            # Update sum/count for average
            if sdl_axis not in self.unknown_axis_stats:
                self.unknown_axis_stats[sdl_axis] = (sdl_value, 1)
            else:
                total, count = self.unknown_axis_stats[sdl_axis]
                self.unknown_axis_stats[sdl_axis] = (total + sdl_value, count + 1)

            min_val, max_val = self.unknown_axis_ranges[sdl_axis]
            total, count = self.unknown_axis_stats[sdl_axis]
            avg_val = total / count if count > 0 else 0

            axis_name = self.sdl_axis_names.get(sdl_axis, "UNKNOWN_AXIS")
            #PyUiLogger.get_logger().error(
            #    f"Received unknown analog input axis = {sdl_axis} ({axis_name}), value = {sdl_value} "
            #    f"(range: min = {min_val}, max = {max_val}, avg = {avg_val:.2f})"
            #)
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
        
    def stop_wifi_services(self):
        PyUiLogger.get_logger().info(f"Stopping WiFi Services")
        MiyooTrimCommon.stop_wifi_services(self)

    def start_wpa_supplicant(self):
        MiyooTrimCommon.start_wpa_supplicant(self)


    def is_wifi_enabled(self):
        return self.system_config.is_wifi_enabled()

    def disable_wifi(self):
        MiyooTrimCommon.disable_wifi(self)

    def enable_wifi(self):
        MiyooTrimCommon.enable_wifi(self)
        
    def get_app_finder(self):
        return MiyooAppFinder()
    
    def parse_favorites(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_favorites()
    
    def parse_recents(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_recents()

    def is_bluetooth_enabled(self):
        try:
            # Run 'ps' to check for bluetoothd process
            result = self.get_running_processes()
            # Check if bluetoothd is in the process list
            return 'bluetoothd' in result.stdout
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error checking bluetoothd status: {e}")
            return False
    
    
    def disable_bluetooth(self):
        PyUiLogger.get_logger().info(f"Disabling Bluetooth")
        ProcessRunner.run(["killall","-15","bluetoothd"])
        time.sleep(0.1)  
        ProcessRunner.run(["killall","-9","bluetoothd"])
        self.system_config.set_bluetooth(0)

    def enable_bluetooth(self):
        if(not self.is_bluetooth_enabled()):
            subprocess.Popen(['./bluetoothd',"-f","/etc/bluetooth/main.conf"],
                            cwd='/usr/libexec/bluetooth/',
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
        self.system_config.set_bluetooth(1)
            
    def perform_startup_tasks(self):
        pass

    def get_favorites_path(self):
        return "/mnt/SDCARD/Saves/pyui-favorites.json"
    
    def get_recents_path(self):
        return "/mnt/SDCARD/Saves/pyui-recents.json"
        
    def get_apps_config_path(self):
        return "/mnt/SDCARD/Saves/pyui-apps.json"

    def get_collections_path(self):
        return "/mnt/SDCARD/Collections/"
    
    def launch_stock_os_menu(self):
        self.run_cmd("/usr/miyoo/bin/runmiyoo-original.sh")

    def get_state_path(self):
        return "/mnt/SDCARD/Saves/pyui-state.json"

    def calibrate_sticks(self):
        from controller.controller import Controller
        sdl2.SDL_QuitSubSystem(sdl2.SDL_INIT_GAMECONTROLLER)
        ProcessRunner.run(["killall","-9","miyoo_inputd"])
        time.sleep(0.5)
        joystick = TrimUIJoystick()
        joystick.open()
        MiyooTrimCommon.run_analog_stick_calibration(self,"Left stick",joystick,"/userdata/joypad.config","L")
        MiyooTrimCommon.run_analog_stick_calibration(self,"Right stick",joystick,"/userdata/joypad_right.config","R")
        subprocess.Popen(["/usr/miyoo/bin/miyoo_inputd"],
                                stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL)
        Controller.re_init_controller()
    
    def remap_buttons(self):
        self.button_remapper.remap_buttons()
 
    def supports_wifi(self):
        return True
    
    def get_game_system_utils(self):
        return self.game_utils
    
    def get_roms_dir(self):
        return "/mnt/SDCARD/Roms/"
    
    def get_save_state_image(self, rom_info: RomInfo):
        return self.get_game_system_utils().get_save_state_image(rom_info)
    
    def get_device_specific_about_info_entries(self):
        return []
