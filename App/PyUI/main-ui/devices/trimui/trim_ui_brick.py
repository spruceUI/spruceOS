import math
from pathlib import Path
import subprocess
import threading
from audio.audio_player_delegate_sdl2 import AudioPlayerDelegateSdl2
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller import DictKeyMappingProvider, KeyWatcherController
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo.system_config import SystemConfig
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.miyoo_trim_mapping_provider import MiyooTrimKeyMappingProvider
from devices.trimui.trim_ui_device import TrimUIDevice
from devices.utils.file_watcher import FileWatcher
from devices.utils.process_runner import ProcessRunner
from display.display import Display
from utils import throttle

from utils.config_copier import ConfigCopier
from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class TrimUIBrick(TrimUIDevice):
    
    TRIMUI_STOCK_CONFIG_LOCATION = "/mnt/UDISK/system.json"

    def __init__(self, device_name, main_ui_mode):
        self.device_name = device_name
        self.audio_player = AudioPlayerDelegateSdl2()
        script_dir = Path(__file__).resolve().parent
        source = script_dir / 'brick-system.json'
        self._load_system_config("/mnt/SDCARD/Saves/trim-ui-brick-system.json", source)

        if(main_ui_mode):
            trim_stock_json_file = script_dir / 'stock/brick.json'
            ConfigCopier.ensure_config(TrimUIBrick.TRIMUI_STOCK_CONFIG_LOCATION, trim_stock_json_file)


            self.miyoo_games_file_parser = MiyooGamesFileParser()        
            self.ensure_wpa_supplicant_conf()
            threading.Thread(target=self.monitor_wifi, daemon=True).start()
            threading.Thread(target=self.startup_init, daemon=True).start()
            self.config_watcher_thread, self.config_watcher_thread_stop_event = FileWatcher().start_file_watcher(
                "/mnt/SDCARD/Saves/trim-ui-brick-system.json", self.on_system_config_changed, interval=0.2, repeat_trigger_for_mtime_granularity_issues=True)
            if(PyUiConfig.enable_button_watchers()):
                from controller.controller import Controller
                #/dev/miyooio if we want to get rid of miyoo_inputd
                # debug in terminal: hexdump  /dev/miyooio
                self.volume_key_watcher = KeyWatcher("/dev/input/event3")
                Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
                volume_key_polling_thread = threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True)
                volume_key_polling_thread.start()
                self.power_key_watcher = KeyWatcher("/dev/input/event1")
                power_key_polling_thread = threading.Thread(target=self.power_key_watcher.poll_keyboard, daemon=True)
                power_key_polling_thread.start()
                # Done to try to account for external systems editting the config file
                
        super().__init__()
            

    def startup_init(self, include_wifi=True):
        self._set_lumination_to_config()
        self._set_contrast_to_config()
        self._set_saturation_to_config()
        self._set_brightness_to_config()
        self._set_hue_to_config()
            
    #Untested
    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        return False

    def should_scale_screen(self):
        return self.is_hdmi_connected()


    def screen_width(self):
        return 1024


    def screen_height(self):
        return 768
    
    

    def output_screen_width(self):
        return 1920


    def output_screen_height(self):
        return 1080

    def get_scale_factor(self):
        if(self.is_hdmi_connected()):
            return 2.25
        else:
            return 1
        
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


    def get_controller_interface(self):
        return KeyWatcherController(event_path="/dev/input/event3", mapping_provider=MiyooTrimKeyMappingProvider(), event_format='llHHi')
    
    def get_device_name(self):
        return self.device_name
        
    def set_theme(self, theme_path: str):
        MiyooTrimCommon.set_theme(TrimUIBrick.TRIMUI_STOCK_CONFIG_LOCATION, theme_path)

    def get_audio_system(self):
        return self.audio_player
    
    def get_core_name_overrides(self, core_name):
        return [core_name, core_name+"-64"]    
    
    def might_require_surface_format_conversion(self):
        return True # RA save state images don't seem to load w/o conversion?
    
        
    def enable_bluetooth(self):
        if(not self.is_bluetooth_enabled()):
            subprocess.Popen(['./bluetoothd',"-f","/etc/bluetooth/main.conf"],
                            cwd='/usr/bin',
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
        self.system_config.set_bluetooth(1)

    def volume_up(self):
        try:
            proc = subprocess.Popen(
                ["sendevent", "/dev/input/event3"],
                stdin=subprocess.PIPE,
                text=True
            )

            proc.stdin.write("1 115 1\n")
            proc.stdin.write("1 115 0\n")
            proc.stdin.write("0 0 0\n")
            proc.stdin.flush()
            proc.stdin.close()

            proc.wait()
        except Exception as e:
            PyUiLogger.get_logger().exception(
                f"Failed to set volume via input events: {e}"
            )

    def volume_down(self):
        try:
            proc = subprocess.Popen(
                ["sendevent", "/dev/input/event3"],
                stdin=subprocess.PIPE,
                text=True
            )

            proc.stdin.write("1 114 1\n")
            proc.stdin.write("1 114 0\n")
            proc.stdin.write("0 0 0\n")
            proc.stdin.flush()
            proc.stdin.close()

            proc.wait()
        except Exception as e:
            PyUiLogger.get_logger().exception(
                f"Failed to set volume via input events: {e}"
            )
