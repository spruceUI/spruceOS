from pathlib import Path
import re
import subprocess
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

os.environ["SDL_VIDEODRIVER"] = "KMSDRM"
os.environ["SDL_RENDER_DRIVER"] = "kmsdrm"

class MiyooFlip(Device):
    
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
        self.system_config = SystemConfig("/userdata/system.json")
        self.miyoo_games_file_parser = MiyooGamesFileParser()        
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
            print("Created missing wpa_supplicant.conf.")
        else:
            print("wpa_supplicant.conf already exists.")

    @property
    def screen_width(self):
        return 640

    @property
    def screen_height(self):
        return 480

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
        return 2 # 2 seconds
    
    
    def _map_system_brightness_to_miyoo_scale(self, true_brightness):
        if(true_brightness >= 255):
            return 10
        elif(true_brightness >= 225):
            return 9
        elif(true_brightness >= 200):
            return 8
        elif(true_brightness >= 175):
            return 7
        elif(true_brightness >= 150):
            return 6
        elif(true_brightness >= 125):
            return 5
        elif(true_brightness >= 100):
            return 4
        elif(true_brightness >= 75):
            return 3
        elif(true_brightness >= 50):
            return 2
        elif(true_brightness >= 25):
            return 1
        else:
            return 0

    def _map_miyoo_scale_to_system_brightness(self, brightness_level):
        if brightness_level == 10:
            return 255
        elif brightness_level == 9:
            return 225
        elif brightness_level == 8:
            return 200
        elif brightness_level == 7:
            return 175
        elif brightness_level == 6:
            return 150
        elif brightness_level == 5:
            return 125
        elif brightness_level == 4:
            return 100
        elif brightness_level == 3:
            return 75
        elif brightness_level == 2:
            return 50
        elif brightness_level == 1:
            return 25
        else: 
            return 1
    
    def _set_brightness_to_config(self):
        with open("/sys/class/backlight/backlight/brightness", "w") as f:
            f.write(str(self._map_miyoo_scale_to_system_brightness(self.system_config.brightness)))


    def lower_brightness(self):
        self.system_config.reload_config()
        if(self.system_config.brightness > 0):
            self.system_config.set_brightness(self.system_config.brightness - 1)
            self.system_config.save_config()
            self._set_brightness_to_config()

    def raise_brightness(self):
        self.system_config.reload_config()
        if(self.system_config.brightness < 10):
            self.system_config.set_brightness(self.system_config.brightness + 1)
            self.system_config.save_config()
            self._set_brightness_to_config()

    @property
    def brightness(self):
        true_brightness = subprocess.check_output(
                ["cat", "/sys/class/backlight/backlight/brightness"],
                text=True
            ).strip()
        return self._map_system_brightness_to_miyoo_scale(int(true_brightness))

    def _set_volume(self, volume):
        if(volume < 0):
            volume = 0
        elif(volume > 100):
            volume = 100

        try:
            
            ProcessRunner.run_and_print(
                ["amixer", "cset", f"name='SPK Volume'", str(volume)],
                check=True
            )
        except subprocess.CalledProcessError as e:
            print(f"Failed to set volume: {e}")

        self.system_config.reload_config()
        self.system_config.set_volume(volume // 5)
        self.system_config.save_config()


    def change_volume(self, amount):
        self._set_volume(self.get_volume() + amount)

    def get_volume(self):
        try:
            output = subprocess.check_output(
                ["amixer", "cget", "name='SPK Volume'"],
                text=True
            )
            match = re.search(r": values=(\d+)", output)
            print(f"Volume is {output}")
            if match:
                return int(match.group(1))
            else:
                print("Volume value not found in amixer output.")
                return 0 # ???
        except subprocess.CalledProcessError as e:
            print(f"Command failed: {e}")
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
            print(f"Unable to convert {original_path} to miyoo path")
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
            print(f"Failed to delete file: {e}")

    def run_game(self, file_path):
        #file_path = /mnt/SDCARD/Roms/FAKE08/Alpine Alpaca.p8
        #miyoo maps it to /media/sdcard0/Emu/FAKE08/../../Roms/FAKE08/Alpine Alpaca.p8
        miyoo_app_path = self.convert_game_path_to_miyoo_path(file_path)
        self.write_cmd_to_run(f'''chmod a+x "/media/sdcard0/Emu/FC/../.emu_setup/standard_launch.sh";"/media/sdcard0/Emu/FC/../.emu_setup/standard_launch.sh" "{miyoo_app_path}"''')

        print(f"About to launch /mnt/SDCARD/Emu/.emu_setup/standard_launch.sh {file_path} | {miyoo_app_path}")
        subprocess.run(["/mnt/SDCARD/Emu/.emu_setup/standard_launch.sh",file_path])
        self.delete_cmd_to_run()

    def run_app(self, args, dir = None):
        print(f"About to launch app {args}")
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
            print(f"Unknown input {sdl_input}")
        return mapping



    def get_wifi_connection_quality_info(self) -> WiFiConnectionQualityInfo:
        try:
            output = subprocess.check_output(
                ["cat", "/proc/net/wireless"],
                text=True
            ).strip().splitlines()
            
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
            return WiFiConnectionQualityInfo(noise_level=0, signal_level=0, link_quality=0)
        

    def is_wifi_up(self):
        result = ProcessRunner.run_and_print(["ip", "link", "show", "wlan0"])
        return "UP" in result.stdout
    
    def restart_wifi_services(self):
        self.stop_wifi_services()
        self.start_wifi_services()

    def wifi_error_detected(self):
        self.wifi_error = True
        
    def monitor_wifi(self):
        self.wifi_error = False
        while True:
            if self.is_wifi_enabled():
                if self.wifi_error or not self.is_wifi_up():
                    self.wifi_error = False
                    PyUiLogger.error("Detected wlan0 disappeared, restarting wifi services")
                    self.restart_wifi_services()
                else:
                    PyUiLogger.debug("WiFi is up")

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
        PyUiLogger.debug(f"Executing {args}")
        result = subprocess.run(args, capture_output=True, text=True, check=check)
        if result.stdout:
            PyUiLogger.debug(f"stdout: {result.stdout.strip()}")
        if result.stderr:
            PyUiLogger.error(f"stderr: {result.stderr.strip()}")

        return result

    def set_wifi_power(self, value):
        with open('/sys/class/rkwifi/wifi_power', 'w') as f:
            f.write(str(value))

    def stop_wifi_services(self):
        ProcessRunner.run_and_print(['killall', '-15', 'wpa_supplicant'])
        time.sleep(0.1)  
        ProcessRunner.run_and_print(['killall', '-9', 'wpa_supplicant'])
        time.sleep(0.1)  
        ProcessRunner.run_and_print(['killall', '-15', 'udhcpc'])
        time.sleep(0.1)  
        ProcessRunner.run_and_print(['killall', '-9', 'udhcpc'])
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
            print("wpa_supplicant started.")
        except Exception as e:
            print(f"Error starting wpa_supplicant: {e}")

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
            print("udhcpc started.")
        except Exception as e:
            print(f"Error starting udhcpc: {e}")


    def start_wifi_services(self):
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
        ProcessRunner.run_and_print(["ifconfig","wlan0","down"])
        print("Running ifconfig wlan0 down")
        self.stop_wifi_services()
        self.get_wifi_status.force_refresh()

    def enable_wifi(self):
        self.system_config.reload_config()
        self.system_config.set_wifi(1)
        self.system_config.save_config()
        ProcessRunner.run_and_print(["ifconfig","wlan0","up"])
        print("Running ifconfig wlan0 up")
        self.start_wifi_services()
        self.get_wifi_status.force_refresh()

    @throttle.limit_refresh(5)
    def get_charge_status(self):
        output = subprocess.check_output(
            ["cat", "/sys/class/power_supply/ac/online"],
            text=True
        )

        if(1 == int(output.strip())):
           return ChargeStatus.CHARGING
        else:
            return ChargeStatus.DISCONNECTED
    
    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        output = subprocess.check_output(
            ["cat", "/sys/class/power_supply/battery/capacity"],
            text=True
        )
        return int(output.strip()) 
    
    def get_app_finder(self):
        return MiyooAppFinder()
    
    def parse_favorites(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_favorites()
    
    def parse_recents(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_recents()

    def get_rom_utils(self):
        return RomUtils("/mnt/SDCARD/Roms/")
    
    
    def is_bluetooth_enabled(self):
        try:
            # Run 'ps' to check for bluetoothd process
            result = self.get_running_processes()
            # Check if bluetoothd is in the process list
            return 'bluetoothd' in result.stdout
        except Exception as e:
            print(f"Error checking bluetoothd status: {e}")
            return False
    
    
    def disable_bluetooth(self):
        ProcessRunner.run_and_print(["killall","-15","bluetoothd"])
        time.sleep(0.1)  
        ProcessRunner.run_and_print(["killall","-9","bluetoothd"])

    def enable_bluetooth(self):
        if(not self.is_bluetooth_enabled()):
            subprocess.Popen(['./bluetoothd',"-f","/etc/bluetooth/main.conf"],
                            cwd='/usr/libexec/bluetooth/',
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
            
    def perform_startup_tasks(self):
        pass