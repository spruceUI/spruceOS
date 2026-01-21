import subprocess
import math
from pathlib import Path
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
from utils import throttle
from utils.config_copier import ConfigCopier

from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class TrimUISmartPro(TrimUIDevice):
    TRIMUI_STOCK_CONFIG_LOCATION = "/mnt/UDISK/system.json"

    def __init__(self, device_name,main_ui_mode):
        self.device_name = device_name
        self.audio_player = AudioPlayerDelegateSdl2()

        script_dir = Path(__file__).resolve().parent
        source = script_dir / 'brick-system.json'
        self._load_system_config("/mnt/SDCARD/Saves/trim-ui-smart-pro-system.json", source)
        if(main_ui_mode):
            trim_stock_json_file = script_dir / 'stock/brick.json'
            ConfigCopier.ensure_config(TrimUISmartPro.TRIMUI_STOCK_CONFIG_LOCATION, trim_stock_json_file)


            self.miyoo_games_file_parser = MiyooGamesFileParser()        
            self.ensure_wpa_supplicant_conf()
            threading.Thread(target=self.monitor_wifi, daemon=True).start()
            threading.Thread(target=self.startup_init, daemon=True).start()
            self.config_watcher_thread, self.config_watcher_thread_stop_event = FileWatcher().start_file_watcher(
                "/mnt/SDCARD/Saves/trim-ui-smart-pro-system.json", self.on_system_config_changed, interval=0.2, repeat_trigger_for_mtime_granularity_issues=True)
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
                
            config_volume = self.system_config.get_volume()
            self._set_volume(config_volume)

        super().__init__()

    def startup_init(self, include_wifi=True):
        self._set_lumination_to_config()
        self._set_contrast_to_config()
        self._set_saturation_to_config()
        self._set_brightness_to_config()
        self._set_hue_to_config()
        config_volume = self.system_config.get_volume()
        self._set_volume(config_volume)

    #Untested
    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        return False

    def should_scale_screen(self):
        return self.is_hdmi_connected()


    def screen_width(self):
        return 1280


    def screen_height(self):
        return 720
    

    def output_screen_width(self):
        return 1920


    def output_screen_height(self):
        return 1080

    def get_scale_factor(self):
        if(self.is_hdmi_connected()):
            return 1.5
        else:
            return 1

    def get_device_name(self):
        return self.device_name
    
    
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
        MiyooTrimCommon.set_theme(TrimUISmartPro.TRIMUI_STOCK_CONFIG_LOCATION, theme_path)

    def get_audio_system(self):
        return self.audio_player
    
    def get_core_name_overrides(self, core_name):
        return [core_name, core_name+"-64"]

            
    def _set_volume(self, user_volume):
        from display.display import Display
        if(user_volume < 0):
            user_volume = 0
        elif(user_volume > 100):
            user_volume = 100
        volume = math.ceil(user_volume * 255//100)
        
        try:
            
            ProcessRunner.run(
                ["amixer", "set", f"'Soft Volume Master'", str(int(volume))],
                check=True
            )

        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to set volume: {e}")

        self.system_config.reload_config()
        self.system_config.set_volume(user_volume)
        self.system_config.save_config()
        Display.volume_changed(user_volume)
        return user_volume
    
    def might_require_surface_format_conversion(self):
        return True # RA save state images don't seem to load w/o conversion?
    
    def enable_bluetooth(self):
        if(not self.is_bluetooth_enabled()):
            subprocess.Popen(['./bluetoothd',"-f","/etc/bluetooth/main.conf"],
                            cwd='/usr/bin',
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
        self.system_config.set_bluetooth(1)
