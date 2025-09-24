from concurrent.futures import Future
from pathlib import Path
import subprocess
import threading
from controller.controller_inputs import ControllerInput
from controller.key_watcher import KeyWatcher
import os
from devices.charge.charge_status import ChargeStatus
from devices.miyoo.flip.miyoo_flip_poller import MiyooFlipPoller
from devices.miyoo.miyoo_device import MiyooDevice
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo.system_config import SystemConfig
from devices.utils.process_runner import ProcessRunner
import sdl2
from utils import throttle
from utils.config_copier import ConfigCopier
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class MiyooA30(MiyooDevice):
    OUTPUT_MIXER = 2
    SOUND_DISABLED = 0

    def __init__(self):
        PyUiLogger.get_logger().info("Initializing Miyoo A30")        
        
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
                
        script_dir = Path(__file__).resolve().parent
        source = script_dir / 'a30-system.json'
        ConfigCopier.ensure_config("/mnt/SDCARD/Saves/a30-system.json", source)
        self.system_config = SystemConfig("/mnt/SDCARD/Saves/a30-system.json")
        self.miyoo_games_file_parser = MiyooGamesFileParser()        
        self._set_lumination_to_config()
        self._set_contrast_to_config()
        self._set_saturation_to_config()
        self._set_brightness_to_config()
        self.ensure_wpa_supplicant_conf()
        self.init_gpio()
        threading.Thread(target=self.monitor_wifi, daemon=True).start()
        self.hardware_poller = MiyooFlipPoller(self)
        threading.Thread(target=self.hardware_poller.continuously_monitor, daemon=True).start()

        if(PyUiConfig.enable_button_watchers()):
            from controller.controller import Controller
            #/dev/miyooio if we want to get rid of miyoo_inputd
            # debug in terminal: hexdump  /dev/miyooio
            self.volume_key_watcher = KeyWatcher("/dev/input/event0")
            Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
            volume_key_polling_thread = threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True)
            volume_key_polling_thread.start()
            self.power_key_watcher = KeyWatcher("/dev/input/event2")
            power_key_polling_thread = threading.Thread(target=self.power_key_watcher.poll_keyboard, daemon=True)
            power_key_polling_thread.start()

        self.unknown_axis_ranges = {}  # axis -> (min, max)
        self.unknown_axis_stats = {}   # axis -> (sum, count)
        self.sdl_axis_names = {
            0: "SDL_CONTROLLER_AXIS_LEFTX",
            1: "SDL_CONTROLLER_AXIS_LEFTY",
            2: "SDL_CONTROLLER_AXIS_RIGHTX",
            3: "SDL_CONTROLLER_AXIS_RIGHTY",
            4: "SDL_CONTROLLER_AXIS_TRIGGERLEFT",
            5: "SDL_CONTROLLER_AXIS_TRIGGERRIGHT"
        }
        config_volume = self.system_config.get_volume()
        self._set_volume(config_volume)
        super().__init__()

    def init_gpio(self):
        try:
            if not os.path.exists("/sys/class/gpio150"):
                with open("/sys/class/gpio/export", "w") as f:
                    f.write("150")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error exportiing gpio150 {e}")

    def are_headphones_plugged_in(self):
        try:
            with open("/sys/class/gpio/gpio150/value", "r") as f:
                value = f.read().strip()
                return "0" == value 
        except (FileNotFoundError, IOError) as e:
            return False
        
    def is_lid_closed(self):
        return False

    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        return False

    @property
    def screen_width(self):
        return 640

    @property
    def screen_height(self):
        return 480
        
    @property
    def screen_rotation(self):
        return 270
    
    @property
    def output_screen_width(self):
        if(self.should_scale_screen()):
            return 1920
        else:
            return self.screen_height
        
    @property
    def output_screen_height(self):
        if(self.should_scale_screen()):
            return 1080
        else:
            return self.screen_widths

    def get_scale_factor(self):
        if(self.is_hdmi_connected()):
            return 2.25
        else:
            return 1
    
    def _set_lumination_to_config(self):
        #with open("/sys/class/backlight/backlight/brightness", "w") as f:
        #    f.write(str(self.map_backlight_from_10_to_full_255(self.system_config.backlight)))
        pass
    
    def _set_contrast_to_config(self):
#        ProcessRunner.run(["modetest", "-M", "rockchip", "-a", "-w", 
#                                    "179:contrast:"+str(self.system_config.contrast * 5)])
        pass
    
    def _set_saturation_to_config(self):
#        ProcessRunner.run(["modetest", "-M", "rockchip", "-a", "-w", 
#                                    "179:saturation:"+str(self.system_config.saturation * 5)])
        pass

    def _set_brightness_to_config(self):
#        ProcessRunner.run(["modetest", "-M", "rockchip", "-a", "-w", 
#                                     "179:brightness:"+str(self.system_config.brightness * 5)])
        pass

    def take_snapshot(self, path):
        return None
    
    @throttle.limit_refresh(15)
    def get_ip_addr_text(self):
        if self.is_wifi_enabled():
            try:
                # Run the system command to get wlan0 info
                result = subprocess.run(
                    ["ip", "addr", "show", "wlan0"],
                    capture_output=True,
                    text=True
                )

                if result.returncode != 0:
                    return "Error"

                # Look for an IPv4 address in the command output
                for line in result.stdout.splitlines():
                    line = line.strip()
                    if line.startswith("inet "):  # Example: "inet 192.168.1.42/24 ..."
                        ip = line.split()[1].split("/")[0]  # Take "192.168.1.42" part
                        return ip

                return "Connecting"  # wlan0 exists but no IP yet

            except Exception:
                return "Error"

        return "Off"

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
    
    def set_wifi_power(self, value):
        # Not implemented on A30
        pass

    def get_bluetooth_scanner(self):
        return None
        
    @property
    def reboot_cmd(self):
        return None

    def get_wpa_supplicant_conf_path(self):
        return "/config/wpa_supplicant.conf"