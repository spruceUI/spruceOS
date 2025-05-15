import array
import ctypes
import fcntl
from pathlib import Path
import re
import subprocess
import sys
import threading
import time
from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from devices.charge.charge_status import ChargeStatus
from devices.device import Device
import os
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo.system_config import SystemConfig
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from devices.wifi.wifi_status import WifiStatus
from games.utils.game_entry import GameEntry
from games.utils.rom_utils import RomUtils
import sdl2
from utils import throttle
from utils.logger import PyUiLogger

class TrimUIBrick(Device):
    
    def __init__(self):
        self.path = self
        self.sdl_button_to_input = {
            sdl2.SDL_CONTROLLER_BUTTON_A: ControllerInput.B,
            sdl2.SDL_CONTROLLER_BUTTON_B: ControllerInput.A,
            sdl2.SDL_CONTROLLER_BUTTON_X: ControllerInput.Y,
            sdl2.SDL_CONTROLLER_BUTTON_Y: ControllerInput.X,
            sdl2.SDL_CONTROLLER_BUTTON_GUIDE: ControllerInput.MENU,
            sdl2.SDL_CONTROLLER_BUTTON_DPAD_UP: ControllerInput.DPAD_UP,
            sdl2.SDL_CONTROLLER_BUTTON_DPAD_DOWN: ControllerInput.DPAD_DOWN,
            sdl2.SDL_CONTROLLER_BUTTON_DPAD_LEFT: ControllerInput.DPAD_LEFT,
            sdl2.SDL_CONTROLLER_BUTTON_DPAD_RIGHT: ControllerInput.DPAD_RIGHT,
            sdl2.SDL_CONTROLLER_BUTTON_LEFTSHOULDER: ControllerInput.L1,
            sdl2.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: ControllerInput.R1,
            sdl2.SDL_CONTROLLER_BUTTON_LEFTSTICK: ControllerInput.L3,
            sdl2.SDL_CONTROLLER_BUTTON_RIGHTSTICK: ControllerInput.R3,
            sdl2.SDL_CONTROLLER_BUTTON_START: ControllerInput.START,
            sdl2.SDL_CONTROLLER_BUTTON_BACK: ControllerInput.SELECT,
        }

        #Idea is if something were to change from he we can reload it
        #so it always has the more accurate data
        self.system_config = SystemConfig("/mnt/UDISK/system.json")


        self.miyoo_games_file_parser = MiyooGamesFileParser()        
        self._set_lumination_to_config()
        self._set_contrast_to_config()
        self._set_saturation_to_config()
        self._set_brightness_to_config()
        self.ensure_wpa_supplicant_conf()
        threading.Thread(target=self.monitor_wifi, daemon=True).start()

    def ensure_wpa_supplicant_conf(self):
        conf_path = Path("/userdata/cfg/wpa_supplicant.conf")
        
        if not conf_path.exists():
            conf_path.parent.mkdir(parents=True, exist_ok=True)  # Ensure /userdata/cfg exists
            conf_content = (
                "ctrl_interface=/var/run/wpa_supplicant\n"
                "update_config=1\n\n"
            )
            with conf_path.open("w") as f:
                f.write(conf_content)
            PyUiLogger.get_logger().info("Created missing wpa_supplicant.conf.")
        else:
            PyUiLogger.get_logger().info("wpa_supplicant.conf already exists.")

    #Untested
    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        return False

    def should_scale_screen(self):
        return self.is_hdmi_connected()

    @property
    def screen_width(self):
        return 1024

    @property
    def screen_height(self):
        return 768
    
    
    @property
    def output_screen_width(self):
        return 1920

    @property
    def output_screen_height(self):
        return 1080

    def get_scale_factor(self):
        if(self.is_hdmi_connected()):
            return 2.25
        else:
            return 1

    @property
    def font_size_small(self):
        return 12
    
    @property
    def font_size_medium(self):
        return 18
    
    @property
    def font_size_large(self):
        return 26
    
    @property
    def large_grid_x_offset(self):
        return 34

    @property
    def large_grid_y_offset(self):
        return 160
    
    @property
    def large_grid_spacing_multiplier(self):
        icon_size = 140
        return icon_size+int(self.large_grid_x_offset/2)
    
    @property
    def power_off_cmd(self):
        return "poweroff"
    
    @property
    def reboot_cmd(self):
        return "reboot"
    
    @property
    def input_timeout_default(self):
        return 1/12 # 12 fps
    
    
    def _map_system_lumination_to_miyoo_scale(self, true_lumination):
        if(true_lumination >= 255):
            return 10
        elif(true_lumination >= 225):
            return 9
        elif(true_lumination >= 200):
            return 8
        elif(true_lumination >= 175):
            return 7
        elif(true_lumination >= 150):
            return 6
        elif(true_lumination >= 125):
            return 5
        elif(true_lumination >= 100):
            return 4
        elif(true_lumination >= 75):
            return 3
        elif(true_lumination >= 50):
            return 2
        elif(true_lumination >= 25):
            return 1
        else:
            return 0

    def _map_miyoo_scale_to_system_lumination(self, lumination_level):
        if lumination_level == 10:
            return 255
        elif lumination_level == 9:
            return 225
        elif lumination_level == 8:
            return 200
        elif lumination_level == 7:
            return 175
        elif lumination_level == 6:
            return 150
        elif lumination_level == 5:
            return 125
        elif lumination_level == 4:
            return 100
        elif lumination_level == 3:
            return 75
        elif lumination_level == 2:
            return 50
        elif lumination_level == 1:
            return 25
        else: 
            return 1
    
    def _set_lumination_to_config(self):
        val = self._map_miyoo_scale_to_system_lumination(self.system_config.backlight)
        try:
            DISP_LCD_SET_BRIGHTNESS = 0x102 
            fd = os.open("/dev/disp", os.O_RDWR)
            if fd > 0:
                # Create a ctypes array equivalent to: unsigned long param[4] = {0, val, 0, 0};
                param = (ctypes.c_ulong * 4)(0, val, 0, 0)
                # Perform ioctl with pointer to param
                fcntl.ioctl(fd, DISP_LCD_SET_BRIGHTNESS, param)
                os.close(fd)
        except PermissionError:
            print("Permission denied: try running as root.")
        except Exception as e:
            print(f"Error setting brightness: {e}")

    def _set_contrast_to_config(self):
        pass
    
    def _set_saturation_to_config(self):
        pass

    def _set_brightness_to_config(self):
        pass

    def lower_lumination(self):
        self.system_config.reload_config()
        if(self.system_config.backlight > 0):
            self.system_config.set_backlight(self.system_config.backlight - 1)
            self.system_config.save_config()
            self._set_lumination_to_config()

    def raise_lumination(self):
        self.system_config.reload_config()
        if(self.system_config.backlight < 10):
            self.system_config.set_backlight(self.system_config.backlight + 1)
            self.system_config.save_config()
            self._set_lumination_to_config()

    @property
    def lumination(self):
        return self.system_config.backlight

    def lower_contrast(self):
        self.system_config.reload_config()
        if(self.system_config.get("colorcontrast") > 1):
            self.system_config.set("colorcontrast",self.system_config.get("colorcontrast") - 1)
            self.system_config.save_config()
            self._set_contrast_to_config()

    def raise_contrast(self):
        self.system_config.reload_config()
        if(self.system_config.get("colorcontrast") < 10): 
            self.system_config.set("colorcontrast",self.system_config.get("colorcontrast") + 1)
            self.system_config.save_config()
            self._set_contrast_to_config()

    @property
    def contrast(self):
        return self.system_config.get("colorcontrast")
    

    def lower_brightness(self):
        self.system_config.reload_config()
        if(self.system_config.get("colorbrightness") > 1):
            self.system_config.set("colorbrightness",self.system_config.get("colorbrightness") - 1)
            self.system_config.save_config()
            self._set_brightness_to_config()

    def raise_brightness(self):
        self.system_config.reload_config()
        if(self.system_config.get("colorbrightness") < 10): 
            self.system_config.set("colorbrightness",self.system_config.get("colorbrightness") + 1)
            self.system_config.save_config()
            self._set_brightness_to_config()


    @property
    def brightness(self):
        return self.system_config.get("colorbrightness")


    def lower_saturation(self):
        self.system_config.reload_config()
        if(self.system_config.get("colorsaturation") > 1): 
            self.system_config.set("colorsaturation",self.system_config.get("colorsaturation") - 1)
            self.system_config.save_config()
            self._set_saturation_to_config()

    def raise_saturation(self):
        self.system_config.reload_config()
        if(self.system_config.get("colorsaturation") < 10): 
            self.system_config.set("colorsaturation",self.system_config.get("colorsaturation") + 1)
            self.system_config.save_config()
            self._set_brightness_to_config()

    @property
    def saturation(self):
        return self.system_config.get("colorsaturation")

    def _set_volume(self, volume):
        if(volume < 0):
            volume = 0
        elif(volume > 100):
            volume = 100

        try:
            
            ProcessRunner.run(
                ["amixer", "cset", f"name='Soft Volume Master'", str(volume)],
                check=True
            )

        except subprocess.CalledProcessError as e:
            PyUiLogger.get_logger().error(f"Failed to set volume: {e}")

        self.system_config.reload_config()
        self.system_config.set_volume(volume // 5)
        self.system_config.save_config()


    def change_volume(self, amount):
        self._set_volume(self.get_volume() + amount)

    def get_volume(self):
        try:
            output = subprocess.check_output(
                ["amixer", "cget", "name='Soft Volume Master'"],
                text=True
            )
            match = re.search(r": values=(\d+)", output)
            if match:
                return int(match.group(1))
            else:
                PyUiLogger.get_logger().info("Volume value not found in amixer output.")
                return 0 # ???
            pass
        except subprocess.CalledProcessError as e:
            PyUiLogger.get_logger().error(f"Command failed: {e}")
            return 0 # ???
        
    def convert_game_path_to_miyoo_path(self,original_path):
        # Define the part of the path to be replaced
        base_dir = "/mnt/SDCARD/Roms/"

        # Check if the original path starts with the base directory
        if original_path.startswith(base_dir):
            # Extract the subdirectory after Roms/
            subdirectory = original_path[len(base_dir):].split(os.sep, 1)[0]
            
            # Construct the new path using the desired format
            new_path = original_path.replace(f"Roms{os.sep}{subdirectory}", f"Emu{os.sep}{subdirectory}{os.sep}..{os.sep}..{os.sep}Roms{os.sep}{subdirectory}")
            new_path = new_path.replace("/mnt/SDCARD/", "/media/sdcard0/")
            return new_path
        else:
            PyUiLogger.get_logger().error(f"Unable to convert {original_path} to miyoo path")
            return original_path
        
    def write_cmd_to_run(self, command):
        with open('/tmp/cmd_to_run.sh', 'w') as file:
            file.write(command)

    def delete_cmd_to_run(self):
        try:
            os.remove('/tmp/cmd_to_run.sh')
        except FileNotFoundError:
            pass  # File doesn't exist, no action needed
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to delete file: {e}")

    def fix_sleep_sound_bug(self):
        pass


    def run_game(self, file_path):
        #file_path = /mnt/SDCARD/Roms/FAKE08/Alpine Alpaca.p8
        #miyoo maps it to /media/sdcard0/Emu/FAKE08/../../Roms/FAKE08/Alpine Alpaca.p8
        miyoo_app_path = self.convert_game_path_to_miyoo_path(file_path)
        self.write_cmd_to_run(f'''chmod a+x "/media/sdcard0/Emu/FC/../.emu_setup/standard_launch.sh";"/media/sdcard0/Emu/FC/../.emu_setup/standard_launch.sh" "{miyoo_app_path}"''')

        self.fix_sleep_sound_bug()
        PyUiLogger.get_logger().debug(f"About to launch /mnt/SDCARD/Emu/.emu_setup/standard_launch.sh {file_path} | {miyoo_app_path}")
        subprocess.run(["/mnt/SDCARD/Emu/.emu_setup/standard_launch.sh",file_path])

        self.delete_cmd_to_run()

    def run_app(self, args, dir = None):
        PyUiLogger.get_logger().debug(f"About to launch app {args}")
        self.fix_sleep_sound_bug()
        if(dir is not None):
            subprocess.run(args, cwd = dir)
        else:
            subprocess.run(args, cwd = dir)

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
    
    def map_input(self, sdl_input):
        mapping = self.sdl_button_to_input.get(sdl_input, ControllerInput.UNKNOWN)
        if(ControllerInput.UNKNOWN == mapping):
            PyUiLogger.get_logger().error(f"Unknown input {sdl_input}")
        return mapping


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
        
        

    def is_wifi_up(self):
        result = ProcessRunner.run(["ip", "link", "show", "wlan0"], print=False)
        return "UP" in result.stdout
    
    def restart_wifi_services(self):
        PyUiLogger.get_logger().info("Restarting WiFi services")
        self.stop_wifi_services()
        self.start_wifi_services()

    def wifi_error_detected(self):
        self.wifi_error = True
        
    
    def connection_seems_up(self):
        try:
            result = ProcessRunner.run(
                ["ping", "-c", "1", "1.1.1.1"],
                timeout=1,
                print=False)
            
            return not ("Network is unreachable") in result.stderr

        except subprocess.TimeoutExpired:
            return False
    
    def monitor_wifi(self):
        self.wifi_error = False
        self.last_successful_ping_time = time.time()
        fail_count = 0
        restart_count = 0
        while True:
            if self.is_wifi_enabled():
                if self.wifi_error or not self.is_wifi_up():
                    self.wifi_error = False
                    fail_count = 0
                    PyUiLogger.get_logger().error("Detected wlan0 disappeared, restarting wifi services")
                    self.restart_wifi_services()
                else:
                    if time.time() - self.last_successful_ping_time > 30:
                        if(self.connection_seems_up()):
                            self.last_successful_ping_time = time.time()
                            fail_count = 0
                            restart_count = 0
                        else:
                            PyUiLogger.get_logger().error("WiFi connection looks to be down")
                            fail_count+=1
                            if(fail_count > 3):
                                if(restart_count > 5):
                                    PyUiLogger.get_logger().error("Cannot get WiFi connection so disabling WiFi")
                                    self.disable_wifi()
                                else:
                                    PyUiLogger.get_logger().error("Going to reinitialize WiFi")
                                    restart_count += 1
                                    self.wifi_error = True


            time.sleep(10)


    @throttle.limit_refresh(10)
    def get_wifi_status(self):
        if(self.is_wifi_enabled()):
            wifi_connection_quality_info = self.get_wifi_connection_quality_info()
            # Composite score out of 100 based on weighted contribution
            # Adjust weights as needed based on empirical testing
            score = (
                (wifi_connection_quality_info.link_quality / 70.0) * 0.5 +          # 50% weight
                (wifi_connection_quality_info.signal_level / 70.0) * 0.3 +        # 30% weight
                ((70 - wifi_connection_quality_info.noise_level) / 70.0) * 0.2    # 20% weight (less noise is better)
            ) * 100

            if score >= 80:
                return WifiStatus.GREAT
            elif score >= 60:
                return WifiStatus.GOOD
            elif score >= 40:
                return WifiStatus.OKAY
            else:
                return WifiStatus.BAD
        else:            
            return WifiStatus.OFF

    def run_and_print(self, args, check = False):
        PyUiLogger.get_logger().debug(f"Executing {args}")
        result = subprocess.run(args, capture_output=True, text=True, check=check)
        if result.stdout:
            PyUiLogger.get_logger().debug(f"stdout: {result.stdout.strip()}")
        if result.stderr:
            PyUiLogger.get_logger().error(f"stderr: {result.stderr.strip()}")

        return result

    def set_wifi_power(self, value):
        pass

    def stop_wifi_services(self):
        PyUiLogger.get_logger().info("Stopping WiFi Services")
        ProcessRunner.run(['killall', '-15', 'wpa_supplicant'])
        time.sleep(0.1)  
        ProcessRunner.run(['killall', '-9', 'wpa_supplicant'])
        time.sleep(0.1)  
        ProcessRunner.run(['killall', '-15', 'udhcpc'])
        time.sleep(0.1)  
        ProcessRunner.run(['killall', '-9', 'udhcpc'])
        time.sleep(0.1)  
        self.set_wifi_power(0)

    def get_running_processes(self):
        #bypass ProcessRunner.run_and_print() as it makes the log too big
        return subprocess.run(['ps', '-f'], capture_output=True, text=True)

    def start_wpa_supplicant(self):
        try:
            # Check if wpa_supplicant is running using ps -f
            result = self.get_running_processes()
            if 'wpa_supplicant' in result.stdout:
                return

            # If not running, start it in the background
            subprocess.Popen([
                'wpa_supplicant',
                '-B',
                '-D', 'nl80211',
                '-i', 'wlan0',
                '-c', '/userdata/cfg/wpa_supplicant.conf'
            ])
            time.sleep(0.5)  # Wait for it to initialize
            PyUiLogger.get_logger().info("wpa_supplicant started.")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error starting wpa_supplicant: {e}")

    def start_udhcpc(self):
        try:
            # Check if wpa_supplicant is running using ps -f
            result = self.get_running_processes()
            if 'udhcpc' in result.stdout:
                return

            # If not running, start it in the background
            subprocess.Popen([
                'udhcpc',
                '-i', 'wlan0'
            ])
            time.sleep(0.5)  # Wait for it to initialize
            PyUiLogger.get_logger().info("udhcpc started.")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error starting udhcpc: {e}")


    def start_wifi_services(self):
        PyUiLogger.get_logger().info("Starting WiFi Services")
        self.set_wifi_power(0)
        time.sleep(1)  
        self.set_wifi_power(1)
        time.sleep(1)  
        self.start_wpa_supplicant()
        self.start_udhcpc()

    def is_wifi_enabled(self):
        return self.system_config.is_wifi_enabled()

    def disable_wifi(self):
        self.system_config.reload_config()
        self.system_config.set_wifi(0)
        self.system_config.save_config()
        ProcessRunner.run(["ifconfig","wlan0","down"])
        self.stop_wifi_services()
        self.get_wifi_status.force_refresh()

    def enable_wifi(self):
        self.system_config.reload_config()
        self.system_config.set_wifi(1)
        self.system_config.save_config()
        ProcessRunner.run(["ifconfig","wlan0","up"])
        self.start_wifi_services()
        self.get_wifi_status.force_refresh()

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

    def get_rom_utils(self):
        return RomUtils("/mnt/SDCARD/Roms/")
    
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