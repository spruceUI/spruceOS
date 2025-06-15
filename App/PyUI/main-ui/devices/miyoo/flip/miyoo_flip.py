from pathlib import Path
import subprocess
import threading
from controller.controller_inputs import ControllerInput
from controller.key_watcher import KeyWatcher
import os
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

class MiyooFlip(MiyooDevice):
    OUTPUT_MIXER = 2
    SOUND_DISABLED = 0

    def __init__(self):
        PyUiLogger.get_logger().info("Initializing Miyoo Flip")        
        
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
        
        os.environ["SDL_VIDEODRIVER"] = "KMSDRM"
        os.environ["SDL_RENDER_DRIVER"] = "kmsdrm"
        
        script_dir = Path(__file__).resolve().parent
        source = script_dir / 'flip-system.json'
        ConfigCopier.ensure_config("/mnt/SDCARD/Saves/flip-system.json", source)
        self.system_config = SystemConfig("/mnt/SDCARD/Saves/flip-system.json")
        self.miyoo_games_file_parser = MiyooGamesFileParser()        
        self._set_lumination_to_config()
        self._set_contrast_to_config()
        self._set_saturation_to_config()
        self._set_brightness_to_config()
        self._set_hue_to_config()
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

        self.init_bluetooth()
        config_volume = self.system_config.get_volume()
        self._set_volume(config_volume)
        super().__init__()

    def init_bluetooth(self):
        try:
            subprocess.Popen(["insmod","/lib/modules/rtk_btusb.ko"],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error running insmod {e}")

        if(not self.is_btmanager_runing()):
            try:
                subprocess.Popen(["/usr/miyoo/bin/btmanager"],
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL)
            except Exception as e:
                PyUiLogger.get_logger().error(f"Error running insmod {e}")

    def is_btmanager_runing(self):
        try:
            # Run 'ps' to check for bluetoothd process
            result = self.get_running_processes()
            # Check if bluetoothd is in the process list
            return 'btmanager' in result.stdout
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error checking bluetoothd status: {e}")
            return False


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
        try:
            with open("/sys/devices/platform/hall-mh248/hallvalue", "r") as f:
                value = f.read().strip()
                return "0" == value 
        except (FileNotFoundError, IOError) as e:
            return False

    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        try:
            # Read the HDMI status from the file
            with open('/sys/class/drm/card0-HDMI-A-1/status', 'r') as f:
                status = f.read().strip()

            # Check if the status is 'disconnected'
            if status.lower() == 'disconnected':
                return False
            else:
                PyUiLogger.get_logger().info(f"HDMI Connected")
                return True
        except FileNotFoundError:
            PyUiLogger.get_logger().error("Error: The file '/sys/class/drm/card0-HDMI-A-1/status' does not exist.")
            return False
        except Exception as e:
            PyUiLogger.get_logger().error(f"An error occurred: {e}")
            return False

    @property
    def screen_width(self):
        return 640

    @property
    def screen_height(self):
        return 480
    
    
    @property
    def output_screen_width(self):
        if(self.should_scale_screen()):
            return 1920
        else:
            return 640
        
    @property
    def output_screen_height(self):
        if(self.should_scale_screen()):
            return 1080
        else:
            return 480

    def get_scale_factor(self):
        if(self.is_hdmi_connected()):
            return 2.25
        else:
            return 1
    
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