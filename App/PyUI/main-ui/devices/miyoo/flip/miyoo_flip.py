import inspect
import json
from pathlib import Path
import subprocess
import threading
import time
from audio.audio_player_delegate_sdl2 import AudioPlayerDelegateSdl2
from controller.controller_inputs import ControllerInput
from controller.key_watcher import KeyWatcher
import os
from controller.sdl.sdl2_controller_interface import Sdl2ControllerInterface
from devices.bluetooth.bluetooth_scanner import BluetoothScanner
from devices.charge.charge_status import ChargeStatus
from devices.miyoo.flip.miyoo_flip_poller import MiyooFlipPoller
from devices.miyoo.miyoo_device import MiyooDevice
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo.system_config import SystemConfig
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.file_watcher import FileWatcher
from devices.utils.process_runner import ProcessRunner
from display.display import Display
from menus.games.utils.rom_info import RomInfo
from menus.settings.timezone_menu import TimezoneMenu
import sdl2
from utils import throttle
from utils.config_copier import ConfigCopier
from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class MiyooFlip(MiyooDevice):
    OUTPUT_MIXER = 2
    SOUND_DISABLED = 0
    MIYOO_STOCK_CONFIG_LOCATION = "/userdata/system.json"

    def __init__(self, device_name, main_ui_mode):
        self.device_name = device_name
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
        self.sdl2_controller_interface = Sdl2ControllerInterface()
        self.audio_player = AudioPlayerDelegateSdl2()

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
        
        self.system_config = None
        if(main_ui_mode):
            script_dir = Path(__file__).resolve().parent
            source = script_dir / 'flip-system.json'
            ConfigCopier.ensure_config("/mnt/SDCARD/Saves/flip-system.json", source)
            self.system_config = SystemConfig("/mnt/SDCARD/Saves/flip-system.json")
            self.miyoo_games_file_parser = MiyooGamesFileParser()        
            miyoo_stock_json_file = script_dir.parent / 'stock/flip.json'
            ConfigCopier.ensure_config(MiyooFlip.MIYOO_STOCK_CONFIG_LOCATION, miyoo_stock_json_file)
            self.hardware_poller = MiyooFlipPoller(self)
            threading.Thread(target=self.hardware_poller.continuously_monitor, daemon=True).start()
            threading.Thread(target=self.startup_init, daemon=True).start()
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
          
            # Done to try to account for external systems editting the config file
            self.config_watcher_thread, self.config_watcher_thread_stop_event = FileWatcher().start_file_watcher(
                "/mnt/SDCARD/Saves/flip-system.json", self.on_system_config_changed, interval=1.0)

        if(self.system_config is None):
            self.system_config = SystemConfig("/mnt/SDCARD/Saves/flip-system.json")

        super().__init__()


    def get_controller_interface(self):
        return self.sdl2_controller_interface

    def on_system_config_changed(self):
        old_volume = self.system_config.get_volume()
        self.system_config.reload_config()
        new_volume = self.system_config.get_volume()
        if(old_volume != new_volume):
            Display.volume_changed(new_volume)

    def startup_init(self):
        self._set_lumination_to_config()
        self._set_contrast_to_config()
        self._set_saturation_to_config()
        self._set_brightness_to_config()
        self._set_hue_to_config()
        self.ensure_wpa_supplicant_conf()
        self.init_gpio()

        if(PyUiConfig.enable_wifi_monitor()):
            PyUiLogger.get_logger().info(f"Starting wifi monitor")
            threading.Thread(target=self.monitor_wifi, daemon=True).start()
            if(self.is_wifi_enabled()):
                if(not self.connection_seems_up()):
                    self.stop_wifi_services()
                self.start_wifi_services()

        self.init_bluetooth()
        config_volume = self.system_config.get_volume()
        self._set_volume(config_volume)
        self.apply_timezone(self.system_config.get_timezone())

    def init_bluetooth(self):
        if(self.system_config.is_bluetooth_enabled()):
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
        else:
            self.disable_bluetooth()

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
            PyUiLogger.get_logger().warning(f"Unable to export gpio150, probably already exported? {e}")

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
        

    #This was from ChatGPT and might be able to be modified to get the current display
    #but currently its capturing an old one which just says Loading...
    def capture_kmsdrm_png(self, output_path="/tmp/screenshot.png", fb_path="/dev/fb0"):
        logger = PyUiLogger.get_logger()

        # Read width/height/stride from sysfs if possible
        try:
            with open("/sys/class/graphics/fb0/virtual_size", "r") as f:
                width_str, height_str = f.read().strip().split(",")
                width, height = int(width_str), int(height_str)
            with open("/sys/class/graphics/fb0/stride", "r") as f:
                stride = int(f.read().strip())
        except Exception as e:
            logger.warning(f"Failed to read fb0 sysfs info: {e}, using defaults")
            width, height, stride = 640, 480, 2560

        # Open framebuffer for reading
        frame_bytes = bytearray()
        with open(fb_path, "rb") as fb:
            for _ in range(height):
                row = fb.read(stride)
                frame_bytes.extend(row[:width*4])  # slice only visible pixels

        # Convert BGRA to RGBA
        img = Image.frombytes("RGBA", (width, height), bytes(frame_bytes), "raw", "BGRA")
        img.save(output_path)
        logger.info(f"Framebuffer saved to {output_path} ({width}x{height})")
        return output_path
            
    def _take_snapshot(self, path):
        ProcessRunner.run(["/mnt/sdcard/spruce/flip/screenshot.sh", path])
        return path

    def take_snapshot(self, path):
        #Currently this takes 0.7s on the flip, way too long to leave enabled
        #return self._take_snapshot(path)
        return None
    
    
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
        caller = inspect.stack()[1].function
        PyUiLogger.get_logger().info(
            f"Called from {caller}: Setting /sys/class/rkwifi/wifi_power to {str(value)}"
        )
        with open('/sys/class/rkwifi/wifi_power', 'w') as f:
            f.write(str(value))

    def get_bluetooth_scanner(self):
        return BluetoothScanner()
    
    @property
    def reboot_cmd(self):
        return "reboot"

    def get_wpa_supplicant_conf_path(self):
        return "/userdata/cfg/wpa_supplicant.conf"

    def get_volume(self):
        return self.system_config.get_volume()


    def _set_volume(self, volume):
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

                # Why is the volume at 5 sometimes broken, but going 10 -> 5 fixes it?
                if(volume == 5):
                    ProcessRunner.run(
                        ["amixer", "cset", f"name='SPK Volume'", str(10)],
                        check=True,
                        print=False
                    )
                    ProcessRunner.run(
                        ["amixer", "cset", f"name='SPK Volume'", str(0)],
                        check=True,
                        print=False
                    )


            
        except subprocess.CalledProcessError as e:
            PyUiLogger.get_logger().error(f"Failed to set volume: {e}")

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
        return MiyooTrimCommon.run_game(self,rom_info, remap_sdcard_path = True)

    def supports_analog_calibration(self):
        return True

    def supports_image_resizing(self):
        return True

    def supports_brightness_calibration(self):
        return True

    def supports_contrast_calibration(self):
        return True

    def supports_saturation_calibration(self):
        return True

    def supports_hue_calibration(self):
        return True

    def get_image_utils(self):
        return FfmpegImageUtils()

    def get_device_name(self):
        return self.device_name
    
    def supports_timezone_setting(self):
        return True

    def prompt_timezone_update(self):
        timezone_menu = TimezoneMenu()
        tz = timezone_menu.ask_user_for_timezone(timezone_menu.list_timezone_files('/usr/share/zoneinfo', verify_via_datetime=True))

        if (tz is not None):
            self.system_config.set_timezone(tz)
            self.apply_timezone(tz)

    def apply_timezone(self, timezone):
        os.environ['TZ'] = timezone
        time.tzset()  
        #If we set the time be sure to
        #export TZ='{timezone}'

    def set_theme(self, theme_path: str):
        MiyooTrimCommon.set_theme(MiyooFlip.MIYOO_STOCK_CONFIG_LOCATION, theme_path)

    def get_audio_system(self):
        return self.audio_player
    
    def get_fw_version(self):
        try:
            with open(f"/usr/miyoo/version") as f:
                return f.read().strip()
        except Exception as e:
            PyUiLogger.get_logger().error(f"Could not read FW version : {e}")
            return "Unknown"
