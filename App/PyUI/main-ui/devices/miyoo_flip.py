import re
import subprocess
from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from devices.charge.charge_status import ChargeStatus
from devices.device import Device
import os
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo.system_config import SystemConfig
from devices.wifi.wifi_status import WifiStatus
from games.utils.game_entry import GameEntry
import sdl2
from utils import throttle

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
            sdl2.SDL_CONTROLLER_BUTTON_DPAD_UP: ControllerInput.DPAD_UP,
            sdl2.SDL_CONTROLLER_BUTTON_DPAD_DOWN: ControllerInput.DPAD_DOWN,
            sdl2.SDL_CONTROLLER_BUTTON_DPAD_LEFT: ControllerInput.DPAD_LEFT,
            sdl2.SDL_CONTROLLER_BUTTON_DPAD_RIGHT: ControllerInput.DPAD_RIGHT,
            sdl2.SDL_CONTROLLER_BUTTON_LEFTSHOULDER: ControllerInput.L1,
            sdl2.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: ControllerInput.R1,
            sdl2.SDL_CONTROLLER_BUTTON_START: ControllerInput.START,
            sdl2.SDL_CONTROLLER_BUTTON_BACK: ControllerInput.SELECT,
        }

        #Idea is if something were to change from he we can reload it
        #so it always has the more accurate data
        self.system_config = SystemConfig("/userdata/system.json")
        self.miyoo_games_file_parser = MiyooGamesFileParser()

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
    
    def _map_system_brightness_to_miyoo_scale(self, true_brightness):
        if(true_brightness >= 220):
            return 10
        elif(true_brightness >= 180):
            return 9
        elif(true_brightness >= 150):
            return 8
        elif(true_brightness >= 120):
            return 7
        elif(true_brightness >= 100):
            return 6
        elif(true_brightness >= 80):
            return 5
        elif(true_brightness >= 60):
            return 4
        elif(true_brightness >= 45):
            return 3
        elif(true_brightness >= 35):
            return 2
        elif(true_brightness >= 20):
            return 1
        else:
            return 0

    def _map_miyoo_scale_to_system_brightness(self, brightness_level):
        if brightness_level == 10:
            return 220
        elif brightness_level == 9:
            return 180
        elif brightness_level == 8:
            return 150
        elif brightness_level == 7:
            return 120
        elif brightness_level == 6:
            return 100
        elif brightness_level == 5:
            return 80
        elif brightness_level == 4:
            return 60
        elif brightness_level == 3:
            return 45
        elif brightness_level == 2:
            return 35
        elif brightness_level == 1:
            return 20
        else: 
            return 1
    
    def lower_brightness(self):

        if(self.brightness > 0):
            self.system_config.reload_config()
            self.system_config.set_brightness(self.brightness-1)
            self.system_config.save_config()
            with open("/sys/class/backlight/backlight/brightness", "w") as f:
                f.write(str(self._map_miyoo_scale_to_system_brightness(self.brightness - 1)))

    def raise_brightness(self):
        if(self.brightness < 10):
            self.system_config.reload_config()
            self.system_config.set_brightness(self.brightness+1)
            self.system_config.save_config()
            with open("/sys/class/backlight/backlight/brightness", "w") as f:
                f.write(str(self._map_miyoo_scale_to_system_brightness(self.brightness + 1)))

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
            subprocess.run(
                ["amixer", "cset", f"name='SPK Volume'", str(volume)],
                check=True
            )
        except subprocess.CalledProcessError as e:
            print(f"Failed to set volume: {e}")

        self.system_config.reload_config()
        self.system_config.set_volume(volume // 5)
        self.system_config.save_config()


    def change_volume(self, amount):
        self._set_volume(self.volume + amount)

    @property
    def volume(self):
        try:
            output = subprocess.check_output(
                ["amixer", "cget", "name='SPK Volume'"],
                text=True
            )
            match = re.search(r": values=(\d+)", output)
            if match:
                return int(match.group(1))
            else:
                print("Volume value not found in amixer output.")
                return 0 # ???
        except subprocess.CalledProcessError as e:
            print(f"Command failed: {e}")
            return 0 # ???

    def run_game(self, file_path):
        print(f"About to launch /mnt/sdcard/Emu/.emu_setup/standard_launch.sh {file_path}")
        subprocess.run(["/mnt/sdcard/Emu/.emu_setup/standard_launch.sh",file_path])

    def run_app(self, args):
        print(f"About to launch app {args}")
        subprocess.run(args)

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
        return self.sdl_button_to_input[sdl_input]
    
    def get_wifi_link_quality_level(self):
        try:
            output = subprocess.check_output(
                ["cat", "/proc/net/wireless"],
                text=True
            ).strip().splitlines()
            
            if len(output) >= 3:
                # The 3rd line contains the actual wireless stats
                data_line = output[2]
                parts = data_line.split()
                
                # parts[2] is the link quality, parts[3] is the level
                link_level = float(parts[3].strip('.'))  # Remove trailing dot
                return int(link_level)
        except Exception as e:
            return 0
    
    @throttle.limit_refresh(15)
    def get_wifi_status(self):
        if(self.is_wifi_enabled()):
            link_quality_level = self.get_wifi_link_quality_level()
            if(link_quality_level >= 70):
                return WifiStatus.GREAT
            elif(link_quality_level >= 50):
                return WifiStatus.GOOD
            elif(link_quality_level >= 30):
                return WifiStatus.OKAY
            else:
                return WifiStatus.BAD
        else:            
            return WifiStatus.OFF
        
    def is_wifi_enabled(self, interface="wlan0"):
        result = subprocess.run(["ip", "link", "show", interface], capture_output=True, text=True)
        return "UP" in result.stdout
    
    
    def disable_wifi(self,interface="wlan0"):
        subprocess.run(["ip", "link", "set", interface, "down"], capture_output=True, text=True)
        self.get_wifi_status.force_refresh()

    def enable_wifi(self,interface="wlan0"):
        subprocess.run(["ip", "link", "set", interface, "up"], capture_output=True, text=True)
        self.get_wifi_status.force_refresh()

    @throttle.limit_refresh(15)
    def get_charge_status(self):
        output = subprocess.check_output(
            ["cat", "/sys/class/power_supply/usb/online"],
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
