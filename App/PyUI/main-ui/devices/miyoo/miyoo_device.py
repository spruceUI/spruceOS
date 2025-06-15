import re
import subprocess
import time
from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from devices.bluetooth.bluetooth_scanner import BluetoothScanner
from devices.charge.charge_status import ChargeStatus
import os
from devices.device_common import DeviceCommon
from devices.miyoo.trim_ui_joystick import TrimUIJoystick
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from menus.settings.button_remapper import ButtonRemapper
import sdl2
from utils import throttle
from utils.logger import PyUiLogger

from devices.device_common import DeviceCommon


class MiyooDevice(DeviceCommon):
    OUTPUT_MIXER = 2
    SOUND_DISABLED = 0

    def __init__(self):
        self.button_remapper = ButtonRemapper(self.system_config)

    def sleep(self):
        with open("/sys/power/mem_sleep", "w") as f:
            f.write("deep")
        with open("/sys/power/state", "w") as f:
            f.write("mem")  

    def ensure_wpa_supplicant_conf(self):
        MiyooTrimCommon.ensure_wpa_supplicant_conf()

    def should_scale_screen(self):
        return self.is_hdmi_connected()

    @property
    def power_off_cmd(self):
        return "poweroff"
    
    @property
    def reboot_cmd(self):
        return "reboot"

    def _set_volume(self, volume):
        from display.display import Display
        if(volume < 0):
            volume = 0
        elif(volume > 100):
            volume = 100

        try:
            
            if(0 == volume):
                ProcessRunner.run(["amixer","sset","Playback Path","OFF"], print=False)
            else:
                PyUiLogger.get_logger().info(f"Setting volume to {volume}")
                ProcessRunner.run(
                    ["amixer", "cset", f"name='SPK Volume'", str(volume)],
                    check=True,
                    print=False
                )

                if(self.are_headphones_plugged_in()):
                    ProcessRunner.run(["amixer","sset","Playback Path","HP"], print=False)
                else:
                    ProcessRunner.run(["amixer","sset","Playback Path","SPK"], print=False)

            
        except subprocess.CalledProcessError as e:
            PyUiLogger.get_logger().error(f"Failed to set volume: {e}")

        self.system_config.reload_config()
        self.system_config.set_volume(volume)
        self.system_config.save_config()
        Display.volume_changed(volume)
        return volume 


    def get_current_mixer_value(self, numid):
        # Run the amixer command and capture output
        result = subprocess.run(
            ['amixer', 'cget', f'numid={numid}'],
            capture_output=True,
            text=True,
            check=True
        )
        output = result.stdout
        
        # Find the line containing ': values=' and extract the number
        for line in reversed(output.splitlines()):
            match = re.search(r': values=(\d+)', line)
            if match:
                return int(match.group(1))
        return None

    def get_volume(self):
        return self.system_config.get_volume()

    def read_volume(self):
        try:
            current_mixer = self.get_current_mixer_value(MiyooDevice.OUTPUT_MIXER)
            if(MiyooDevice.SOUND_DISABLED == current_mixer):
                return 0
            else:
                output = subprocess.check_output(
                    ["amixer", "cget", "name='SPK Volume'"],
                    text=True
                )
                match = re.search(r": values=(\d+)", output)
                if match:
                    return int(match.group(1))
                else:
                    PyUiLogger.get_logger().info("Volume value not found in amixer output.")
                    return 0 # ???
        except subprocess.CalledProcessError as e:
            PyUiLogger.get_logger().error(f"Command failed: {e}")
            return 0 # ???

    def fix_sleep_sound_bug(self):
        config_volume = self.system_config.get_volume()
        PyUiLogger.get_logger().info(f"Restoring volume to {config_volume}")
        ProcessRunner.run(["amixer", "cset","numid=2", "0"])
        ProcessRunner.run(["amixer", "cset","numid=5", "0"])
        if(self.are_headphones_plugged_in()):
            ProcessRunner.run(["amixer", "cset","numid=2", "3"])
        elif(0 == config_volume):
            ProcessRunner.run(["amixer", "cset","numid=2", "0"])
        else:
            ProcessRunner.run(["amixer", "cset","numid=2", "2"])
        self._set_volume(config_volume)

    def run_game(self, rom_info: RomInfo) -> subprocess.Popen:
        return MiyooTrimCommon.run_game(self,rom_info)

    def run_app(self, args, dir = None):
        MiyooTrimCommon.run_app(self, args, dir)

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
        

    def set_wifi_power(self, value):
        PyUiLogger.get_logger().info(f"Setting /sys/class/rkwifi/wifi_power to {str(value)}")
        with open('/sys/class/rkwifi/wifi_power', 'w') as f:
            f.write(str(value))

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
        with open("/sys/class/power_supply/ac/online", "r") as f:
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
        try:
            # Run 'ps' to check for bluetoothd process
            result = self.get_running_processes()
            # Check if bluetoothd is in the process list
            return 'bluetoothd' in result.stdout
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error checking bluetoothd status: {e}")
            return False
    
    
    def disable_bluetooth(self):
        ProcessRunner.run(["killall","-15","bluetoothd"])
        time.sleep(0.1)  
        ProcessRunner.run(["killall","-9","bluetoothd"])

    def enable_bluetooth(self):
        if(not self.is_bluetooth_enabled()):
            subprocess.Popen(['./bluetoothd',"-f","/etc/bluetooth/main.conf"],
                            cwd='/usr/libexec/bluetooth/',
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
            
    def perform_startup_tasks(self):
        pass

    def get_bluetooth_scanner(self):
        return BluetoothScanner()

    def get_favorites_path(self):
        return "/mnt/SDCARD/Saves/pyui-favorites.json"
    
    def get_recents_path(self):
        return "/mnt/SDCARD/Saves/pyui-recents.json"
    
    def launch_stock_os_menu(self):
        self.run_app("/usr/miyoo/bin/runmiyoo-original.sh")

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


    def supports_analog_calibration(self):
        return True
    
    def remap_buttons(self):
        self.button_remapper.remap_buttons()