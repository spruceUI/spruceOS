import fcntl
from pathlib import Path
import struct
import subprocess
import threading
import time
from audio.audio_player_delegate_sdl2 import AudioPlayerDelegateSdl2
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher import KeyWatcher
import os
from controller.key_watcher_controller import DictKeyMappingProvider, KeyWatcherController
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.charge.charge_status import ChargeStatus
from devices.miyoo.miyoo_device import MiyooDevice
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo.system_config import SystemConfig
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.file_watcher import FileWatcher
from devices.utils.process_runner import ProcessRunner
from display.display import Display
from menus.games.utils.rom_info import RomInfo
from utils import throttle
from utils.config_copier import ConfigCopier
from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class MiyooA30(MiyooDevice):
    OUTPUT_MIXER = 2
    SOUND_DISABLED = 0
    MIYOO_STOCK_CONFIG_LOCATION = "/config/system.json"

    def __init__(self, device_name, main_ui_mode):
        self.device_name = device_name
        self.audio_player = AudioPlayerDelegateSdl2()
        script_dir = Path(__file__).resolve().parent
        source = script_dir / 'a30-system.json'
        self._load_system_config("/mnt/SDCARD/Saves/a30-system.json", source)

        if(main_ui_mode):
            self.miyoo_games_file_parser = MiyooGamesFileParser()        
            self.ensure_wpa_supplicant_conf()
            miyoo_stock_json_file = script_dir.parent / 'stock/a30.json'
            ConfigCopier.ensure_config(MiyooA30.MIYOO_STOCK_CONFIG_LOCATION, miyoo_stock_json_file)

            threading.Thread(target=self.monitor_wifi, daemon=True).start()
            #self.hardware_poller = MiyooFlipPoller(self)
            #threading.Thread(target=self.hardware_poller.continuously_monitor, daemon=True).start()
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
            super().__init__()
            # Done to try to account for external systems editting the config file
            self.config_watcher_thread, self.config_watcher_thread_stop_event = FileWatcher().start_file_watcher(
                "/mnt/SDCARD/Saves/a30-system.json", self.on_system_config_changed, interval=0.2, repeat_trigger_for_mtime_granularity_issues=True)


    def power_off_cmd(self):
        return "poweroff"


    def startup_init(self, include_wifi=True):
        self._set_lumination_to_config()
        self._set_screen_settings_to_config()
        self.init_gpio()
        config_volume = self.system_config.get_volume()
        self._set_volume(config_volume)


    def on_system_config_changed(self):
        old_volume = self.system_config.get_volume()
        self.system_config.reload_config()
        new_volume = self.system_config.get_volume()
        if(old_volume != new_volume):
            Display.volume_changed(new_volume)


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


    def screen_width(self):
        return 640


    def screen_height(self):
        return 480
        

    def screen_rotation(self):
        return 270
    

    def output_screen_width(self):
        if(self.should_scale_screen()):
            return 1920
        else:
            return self.screen_height()
        

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
        DISP_LCD_SET_BRIGHTNESS = 0x102
        try:
            fd = os.open("/dev/disp", os.O_RDWR)
        except OSError as e:
            PyUiLogger.get_logger().warning(f"Failed to open /dev/disp: {e}")
            return

        param = struct.pack('LLLL', 0, self.map_backlight_from_10_to_full_255(self.system_config.backlight, min_level=10), 0, 0)

        try:
            fcntl.ioctl(fd, DISP_LCD_SET_BRIGHTNESS, param)
        except OSError as e:
            PyUiLogger.get_logger().warning(f"ioctl failed: {e}")
        finally:
            os.close(fd)

    def supports_brightness_calibration(self):
        return True

    def supports_contrast_calibration(self):
        return True

    def supports_saturation_calibration(self):
        return True

    def supports_hue_calibration(self):
        return True

    def _set_contrast_to_config(self):
        self._set_screen_settings_to_config()
    
    def _set_saturation_to_config(self):
        self._set_screen_settings_to_config()

    def _set_brightness_to_config(self):
        self._set_screen_settings_to_config()

    def _set_hue_to_config(self):
        self._set_screen_settings_to_config()

    def _set_screen_settings_to_config(self):
        try:
            enable = "1"
            brightness = str(self.system_config.brightness*5)
            contrast = str(self.system_config.contrast*5)
            saturation = str(self.system_config.saturation*5)
            hue = str(self.system_config.hue*5)
            values = ",".join([enable, brightness, contrast, saturation, hue])

            with open("/sys/devices/virtual/disp/disp/attr/enhance", "w") as f:
                f.write(values)
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Failed to set screen settings: {e}")

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
        

    def reboot_cmd(self):
        return None

    def get_wpa_supplicant_conf_path(self):
        return PyUiConfig.get_wpa_supplicant_conf_file_location("/config/wpa_supplicant.conf")

    def get_volume(self):
        return self.system_config.get_volume()

    def _set_volume(self, volume):
        try:
            scaled = round(255 * max(0, min(100, volume)) / 100)
            ProcessRunner.run(["amixer","set","Soft Volume Master",str(scaled)], print=True)            
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to set volume: {e}")

        return volume 

    def fix_sleep_sound_bug(self):
        config_volume = self.system_config.get_volume()
        self._set_volume(config_volume)

    def run_game(self, rom_info: RomInfo) -> subprocess.Popen:
        def delayed_fix():
            total_time = 2.0
            interval = 0.1
            elapsed = 0.0
            config_volume = self.system_config.get_volume()
            while elapsed < total_time:
                time.sleep(interval)
                elapsed += interval 
                self._set_volume(config_volume)

        # Start the thread
        threading.Thread(target=delayed_fix, daemon=True).start()
        return MiyooTrimCommon.run_game(self,rom_info)

    def supports_analog_calibration(self):
        return False

    def supports_image_resizing(self):
        return True


    def get_image_utils(self):
        return FfmpegImageUtils()

    def get_device_name(self):
        return self.device_name


    def get_controller_interface(self):
        key_mappings = {}  
        key_mappings[KeyEvent(1, 57, 1)] = [InputResult(ControllerInput.A, KeyState.PRESS)]   
        key_mappings[KeyEvent(1, 57, 0)] = [InputResult(ControllerInput.A, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 29, 1)] = [InputResult(ControllerInput.B, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 29, 0)] = [InputResult(ControllerInput.B, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 56, 1)] = [InputResult(ControllerInput.Y, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 56, 0)] = [InputResult(ControllerInput.Y, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 42, 1)] = [InputResult(ControllerInput.X, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 42, 0)] = [InputResult(ControllerInput.X, KeyState.RELEASE)]

        key_mappings[KeyEvent(1, 103, 1)] = [InputResult(ControllerInput.DPAD_UP, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 103, 0)] = [InputResult(ControllerInput.DPAD_UP, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 108, 1)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 108, 0)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 105, 1)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 105, 0)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 106, 1)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 106, 0)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.RELEASE)]

        key_mappings[KeyEvent(1, 15, 1)] = [InputResult(ControllerInput.L1, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 15, 0)] = [InputResult(ControllerInput.L1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 18, 1)] = [InputResult(ControllerInput.L2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 18, 0)] = [InputResult(ControllerInput.L2, KeyState.RELEASE)]  

        key_mappings[KeyEvent(1, 14, 1)] = [InputResult(ControllerInput.R1, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 14, 0)] = [InputResult(ControllerInput.R1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 20, 1)] = [InputResult(ControllerInput.R2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 20, 0)] = [InputResult(ControllerInput.R2, KeyState.RELEASE)]  

        key_mappings[KeyEvent(1, 28, 1)] = [InputResult(ControllerInput.START, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 28, 0)] = [InputResult(ControllerInput.START, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 97, 1)] = [InputResult(ControllerInput.SELECT, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 97, 0)] = [InputResult(ControllerInput.SELECT, KeyState.RELEASE)]

        key_mappings[KeyEvent(1, 1, 1)] = [InputResult(ControllerInput.MENU, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 1, 0)] = [InputResult(ControllerInput.MENU, KeyState.RELEASE)]  

        return KeyWatcherController(event_path="/dev/input/event3", mapping_provider=DictKeyMappingProvider(key_mappings))

    def set_theme(self, theme_path: str):
        MiyooTrimCommon.set_theme(MiyooA30.MIYOO_STOCK_CONFIG_LOCATION, theme_path)

    def get_audio_system(self):
        return self.audio_player
    
        
    def get_fw_version(self):
        try:
            with open(f"/usr/miyoo/version") as f:
                return f.read().strip()
        except Exception as e:
            PyUiLogger.get_logger().error(f"Could not read FW version : {e}")
            return "Unknown"

    def get_core_name_overrides(self, core_name):
        return [core_name, core_name+"-32"]

    def get_core_for_game(self, game_system_config, rom_file_path):
        core = game_system_config.get_effective_menu_selection("Emulator", rom_file_path)
        if(core is None):
            core = game_system_config.get_effective_menu_selection("Emulator_A30", rom_file_path)
        return core