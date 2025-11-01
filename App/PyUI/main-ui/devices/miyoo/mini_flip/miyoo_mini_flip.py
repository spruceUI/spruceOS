from concurrent.futures import Future
import ctypes
import fcntl
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import threading
import time
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher import KeyWatcher
import os
from controller.key_watcher_controller_miyoo_mini import InputResult, KeyEvent, KeyWatcherControllerMiyooMini
from devices.charge.charge_status import ChargeStatus
from devices.miyoo.flip.miyoo_flip_poller import MiyooFlipPoller
from devices.miyoo.mini_flip.miyoo_mini_flip_shared_memory_writer import MiyooMiniFlipSharedMemoryWriter
from devices.miyoo.miyoo_device import MiyooDevice
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo.system_config import SystemConfig
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.file_watcher import FileWatcher
from devices.utils.process_runner import ProcessRunner
from display.display import Display
from menus.games.utils.rom_info import RomInfo
import sdl2
from utils import throttle
from utils.config_copier import ConfigCopier
from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

MAX_VOLUME = 20
MIN_RAW_VALUE = -60
MAX_RAW_VALUE = 30

MI_AO_SETVOLUME = 0x4008690b
MI_AO_GETVOLUME = 0xc008690c
MI_AO_SETMUTE   = 0x4008690d

class MiyooMiniFlip(MiyooDevice):
    OUTPUT_MIXER = 2
    SOUND_DISABLED = 0


    def __init__(self, device_name):
        self.device_name = device_name
        PyUiLogger.get_logger().info("Initializing Miyoo Mini Flip")        
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
        source = script_dir / 'mini-flip-system.json'
        ConfigCopier.ensure_config("/mnt/SDCARD/Saves/mini-flip-system.json", source)
        self.system_config = SystemConfig("/mnt/SDCARD/Saves/mini-flip-system.json")
        self.miyoo_mini_flip_shared_memory_writer = MiyooMiniFlipSharedMemoryWriter()
        self.miyoo_games_file_parser = MiyooGamesFileParser()        
        self._set_lumination_to_config()
        self._set_contrast_to_config()
        self._set_saturation_to_config()
        self._set_brightness_to_config()
        self.ensure_wpa_supplicant_conf()
        self.init_gpio()
        #self.hardware_poller = MiyooFlipPoller(self)
        #threading.Thread(target=self.hardware_poller.continuously_monitor, daemon=True).start()

        if(PyUiConfig.enable_button_watchers()):
            from controller.controller import Controller
            #/dev/miyooio if we want to get rid of miyoo_inputd
            # debug in terminal: hexdump  /dev/miyooio
            self.volume_key_watcher = KeyWatcher("/dev/input/event0")
            Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
            volume_key_polling_thread = threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True)
            volume_key_polling_thread.start()

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
        self.mainui_volume = None
        threading.Thread(target=self.startup_init, daemon=True).start()
        self.mainui_config_thread, self.mainui_config_thread_stop_event = FileWatcher().start_file_watcher(
            "/appconfigs/system.json", self.on_mainui_config_change, interval=1.0)
        super().__init__()

    def on_mainui_config_change(self):
        path = "/appconfigs/system.json"
        if not os.path.exists(path):
            PyUiLogger.get_logger().warning(f"File not found: {path}")
            return

        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)

            old_volume = self.mainui_volume
            self.mainui_volume = data.get("vol")
            if(old_volume != self.mainui_volume):
                Display.volume_changed(self.mainui_volume * 5)

        except Exception as e:
            PyUiLogger.get_logger().warning(f"Error reading {path}: {e}")
            return None

    def startup_init(self):
        config_volume = self.system_config.get_volume()
        self._set_volume(config_volume)
        if(self.is_wifi_enabled()):
            self.start_wifi_services()
        self.on_mainui_config_change()

    def get_controller_interface(self):
        key_mappings = {}  
        key_mappings[KeyEvent(1, 57, 0)] = [InputResult(ControllerInput.A, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 57, 1)] = [InputResult(ControllerInput.A, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 29, 0)] = [InputResult(ControllerInput.B, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 29, 1)] = [InputResult(ControllerInput.B, KeyState.PRESS)]   
        key_mappings[KeyEvent(1, 56, 0)] = [InputResult(ControllerInput.Y, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 56, 1)] = [InputResult(ControllerInput.Y, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 42, 0)] = [InputResult(ControllerInput.X, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 42, 1)] = [InputResult(ControllerInput.X, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 28, 0)] = [InputResult(ControllerInput.START, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 28, 1)] = [InputResult(ControllerInput.START, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 97, 0)] = [InputResult(ControllerInput.SELECT, KeyState.RELEASE)]   
        key_mappings[KeyEvent(1, 97, 1)] = [InputResult(ControllerInput.SELECT, KeyState.PRESS)]   

        key_mappings[KeyEvent(1, 1, 0)] = [InputResult(ControllerInput.MENU, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 1, 1)] = [InputResult(ControllerInput.MENU, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 15, 0)] = [InputResult(ControllerInput.L2, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 15, 1)] = [InputResult(ControllerInput.L2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 20, 0)] = [InputResult(ControllerInput.R1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 20, 1)] = [InputResult(ControllerInput.R1, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 14, 0)] = [InputResult(ControllerInput.R2, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 14, 1)] = [InputResult(ControllerInput.R2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 18, 0)] = [InputResult(ControllerInput.L1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 18, 1)] = [InputResult(ControllerInput.L1, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 103, 1)] = [InputResult(ControllerInput.DPAD_UP, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 103, 0)] = [InputResult(ControllerInput.DPAD_UP, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 108, 1)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 108, 0)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 105, 1)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 105, 0)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 106, 1)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 106, 0)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.RELEASE)]

        
        return KeyWatcherControllerMiyooMini(event_path="/dev/input/event0", key_mappings=key_mappings)

    def init_gpio(self):
        #self.init_sleep_gpio()
        pass

    def init_sleep_gpio(self):
        try:
            if not os.path.exists("/sys/class/export"):
                with open("/sys/class/gpio/export", "w") as f:
                    f.write("4")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error exporting gpio 4 {e}")


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
        return 750

    @property
    def screen_height(self):
        return 560
        
    @property
    def screen_rotation(self):
        return 0
    
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
            return self.screen_width

    def get_scale_factor(self):
        if(self.is_hdmi_connected()):
            return 2.25
        else:
            return 1
    
    def _set_lumination_to_config(self):
        # Miyoo internally has lumination but it does not work
        #self.miyoo_mini_flip_shared_memory_writer.set_lumination(self.system_config.backlight)
        self.miyoo_mini_flip_shared_memory_writer.set_brightness(self.system_config.backlight)

    def _set_contrast_to_config(self):
        #Doesn't seem to work?
        #self.miyoo_mini_flip_shared_memory_writer.set_contrast(self.system_config.contrast)
        pass
    
    def _set_saturation_to_config(self):
        #Doesn't seem to work?
        #self.miyoo_mini_flip_shared_memory_writer.set_saturation(self.system_config.saturation)
        pass

    def _set_brightness_to_config(self):
        #Doesn't seem to work?
        #self.miyoo_mini_flip_shared_memory_writer.set_brightness(self.system_config.brightness)
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
        try:
            # Run axp_test and parse JSON
            result = subprocess.run(
                ["/customer/app/axp_test"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=2
            )
            data = json.loads(result.stdout.strip())
            charging = int(data.get("charging", 0))
            
            if charging == 0:
                return ChargeStatus.DISCONNECTED
            else:
                return ChargeStatus.CHARGING
        except Exception:
            return ChargeStatus.DISCONNECTED

    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        try:
            # Run axp_test and capture its JSON output
            result = subprocess.run(
                ["/customer/app/axp_test"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=2
            )
            data = json.loads(result.stdout.strip())
            return data.get("battery", 0)
        except Exception:
            return 0
    

    def start_wifi_services(self):
        try:
            # Check if system already has an IP address
            result = subprocess.run(
                ["ip", "route", "get", "1"],
                capture_output=True,
                text=True
            )

            # Extract the last field (the IP) like `awk '{print $NF;exit}'`
            parts = result.stdout.strip().split()
            ip = parts[-1] if parts else ""

            if not ip:
                PyUiLogger.get_logger().info("Wifi is disabled - trying to enable it...")

                subprocess.run(["insmod", "/mnt/SDCARD/8188fu.ko"])
                subprocess.run(["ifconfig", "lo", "up"])
                subprocess.run(["/customer/app/axp_test", "wifion"])
                time.sleep(2)
                subprocess.run(["ifconfig", "wlan0", "up"])
                subprocess.run([
                    "wpa_supplicant",
                    "-B",
                    "-D", "nl80211",
                    "-i", "wlan0",
                    "-c", "/appconfigs/wpa_supplicant.conf"
                ])
                subprocess.run(["udhcpc", "-i", "wlan0", "-s", "/etc/init.d/udhcpc.script"])
                time.sleep(3)
                os.system("clear")

        except Exception as e:
            PyUiLogger.get_logger().error(f"Error enabling WiFi: {e}")


    def set_wifi_power(self, value):
        if(0 == value):
            ProcessRunner.run(["ifconfig", "wlan0", "down"])

    def get_bluetooth_scanner(self):
        return None
        
    @property
    def reboot_cmd(self):
        return "reboot"

    def get_wpa_supplicant_conf_path(self):
        return "/appconfigs/wpa_supplicant.conf"

    def get_volume(self):
        try:
            return self.mainui_volume * 5
        except:
            return 0
        
    def _set_volume_raw(self, value: int, add: int = 0) -> int:
        try:
            fd = os.open("/dev/mi_ao", os.O_RDWR)
        except OSError:
            return 0

        # Prepare buffers
        buf2 = (ctypes.c_int * 2)(0, 0)
        buf1 = (ctypes.c_uint64 * 2)(ctypes.sizeof(buf2), ctypes.cast(buf2, ctypes.c_void_p).value)

        # Get previous volume
        fcntl.ioctl(fd, MI_AO_GETVOLUME, buf1)
        prev_value = buf2[1]

        if add:
            value = prev_value + add
        else:
            value += MIN_RAW_VALUE

        # Clamp value
        value = max(MIN_RAW_VALUE, min(MAX_RAW_VALUE, value))

        if value == prev_value:
            os.close(fd)
            return prev_value

        buf2[1] = value
        fcntl.ioctl(fd, MI_AO_SETVOLUME, buf1)

        # Handle mute
        if prev_value <= MIN_RAW_VALUE < value:
            buf2[1] = 0
            fcntl.ioctl(fd, MI_AO_SETMUTE, buf1)
        elif prev_value > MIN_RAW_VALUE >= value:
            buf2[1] = 1
            fcntl.ioctl(fd, MI_AO_SETMUTE, buf1)

        os.close(fd)
        return value


    def _set_volume(self, volume: int) -> int:
        #Breaks keymon somehow
        if(False):
            volume = max(0, min(MAX_VOLUME, volume))

            volume_raw = 0
            if volume != 0:
                volume_raw = round(48 * math.log10(1 + volume))  # volume curve

            self._set_volume_raw(volume_raw, 0)
        return volume

    def fix_sleep_sound_bug(self):
        config_volume = self.system_config.get_volume()
        self._set_volume(config_volume)


    def run_game(self, rom_info: RomInfo) -> subprocess.Popen:
        preload_path = "/mnt/SDCARD/miyoo/app/../lib/libpadsp.so"
        if os.path.exists(preload_path):
            run_prefix = f"LD_PRELOAD={preload_path} "
        else:
            run_prefix = "LD_PRELOAD=/customer/lib/libpadsp.so "
        return MiyooTrimCommon.run_game(self, rom_info, run_prefix=run_prefix)

    def double_init_sdl_display(self):
        return True
            
    def max_texture_width(self):
        return 800
                    
    def max_texture_height(self):
        return 600

    def get_guaranteed_safe_max_text_char_count(self):
        return 35

    def supports_volume(self):
        return True #can read but not write

    def supports_analog_calibration(self):
        return False

    def supports_image_resizing(self):
        return True

    def supports_brightness_calibration(self):
        return False

    def supports_contrast_calibration(self):
        return False

    def supports_saturation_calibration(self):
        return False

    def supports_hue_calibration(self):
        return False
    
    def supports_popup_menu(self):
        return False
    
    def get_image_utils(self):
        return FfmpegImageUtils()

    def get_boxart_small_resize_dimensions(self):
        return 400,300

    def get_boxart_medium_resize_dimensions(self):
        return 400,300

    def get_boxart_large_resize_dimensions(self):
        return 400,300
    
    def get_device_name(self):
        return self.device_name