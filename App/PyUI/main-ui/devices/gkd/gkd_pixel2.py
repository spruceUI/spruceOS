from pathlib import Path
import os
import threading
from audio.audio_player_delegate_sdl2 import AudioPlayerDelegateSdl2
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller import DictKeyMappingProvider, KeyWatcherController
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.gkd.gkd_device import GKDDevice
from devices.gkd.connman_wifi_scanner import ConnmanWiFiScanner
from devices.gkd.connman_wifi_menu import ConnmanWifiMenu
from devices.utils.file_watcher import FileWatcher
from devices.utils.process_runner import ProcessRunner
from menus.settings.timezone_menu import TimezoneMenu
from utils import throttle

from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class GKDPixel2(GKDDevice):
    def __init__(self, device_name, main_ui_mode):
        self.device_name = device_name
        self.audio_player = AudioPlayerDelegateSdl2()
        script_dir = Path(__file__).resolve().parent
        source = script_dir / 'pixel2-system.json'
        self._load_system_config("/mnt/SDCARD/Saves/gkd-pixel2-system.json", source)

        if(main_ui_mode):
            self.miyoo_games_file_parser = MiyooGamesFileParser()        
            threading.Thread(target=self.monitor_wifi, daemon=True).start()
            threading.Thread(target=self.startup_init, daemon=True).start()
            self.config_watcher_thread, self.config_watcher_thread_stop_event = FileWatcher().start_file_watcher(
                "/mnt/SDCARD/Saves/gkd-pixel2-system.json", self.on_system_config_changed, interval=0.2, repeat_trigger_for_mtime_granularity_issues=True)
            if(PyUiConfig.enable_button_watchers()):
                from controller.controller import Controller
                #/dev/miyooio if we want to get rid of miyoo_inputd
                # debug in terminal: hexdump  /dev/miyooio
                self.volume_key_watcher = KeyWatcher("/dev/input/event1")
                Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
                volume_key_polling_thread = threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True)
                volume_key_polling_thread.start()
                self.power_key_watcher = KeyWatcher("/dev/input/event0")
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
        config_volume = self.system_config.get_volume()
        self._set_volume(config_volume)
            
    #Untested
    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        return False

    def should_scale_screen(self):
        return self.is_hdmi_connected()

    def screen_width(self):
        return 640

    def screen_height(self):
        return 480

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
        return False

    def supports_contrast_calibration(self):
        return False

    def supports_saturation_calibration(self):
        return False

    def supports_hue_calibration(self):
        return False

    def get_image_utils(self):
        return FfmpegImageUtils()


    def get_controller_interface(self):
        key_mappings = {}  
        key_mappings[KeyEvent(1, 304, 0)] = [InputResult(ControllerInput.B, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 304, 1)] = [InputResult(ControllerInput.B, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 305, 0)] = [InputResult(ControllerInput.A, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 305, 1)] = [InputResult(ControllerInput.A, KeyState.PRESS)]   
        key_mappings[KeyEvent(1, 307, 0)] = [InputResult(ControllerInput.X, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 307, 1)] = [InputResult(ControllerInput.X, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 308, 0)] = [InputResult(ControllerInput.Y, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 308, 1)] = [InputResult(ControllerInput.Y, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 544, 1)] = [InputResult(ControllerInput.DPAD_UP, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 544, 0)] = [InputResult(ControllerInput.DPAD_UP, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 545, 1)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 545, 0)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 546, 1)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 546, 0)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 547, 1)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 547, 0)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.RELEASE)]

        key_mappings[KeyEvent(1, 310, 1)] = [InputResult(ControllerInput.L1, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 310, 0)] = [InputResult(ControllerInput.L1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 312, 1)] = [InputResult(ControllerInput.L2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 312, 0)] = [InputResult(ControllerInput.L2, KeyState.RELEASE)]  

        key_mappings[KeyEvent(1, 311, 1)] = [InputResult(ControllerInput.R1, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 311, 0)] = [InputResult(ControllerInput.R1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 313, 1)] = [InputResult(ControllerInput.R2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 313, 0)] = [InputResult(ControllerInput.R2, KeyState.RELEASE)]  

        key_mappings[KeyEvent(1, 315, 1)] = [InputResult(ControllerInput.START, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 315, 0)] = [InputResult(ControllerInput.START, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 314, 1)] = [InputResult(ControllerInput.SELECT, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 314, 0)] = [InputResult(ControllerInput.SELECT, KeyState.RELEASE)]

        key_mappings[KeyEvent(1, 704, 1)] = [InputResult(ControllerInput.MENU, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 704, 0)] = [InputResult(ControllerInput.MENU, KeyState.RELEASE)]  

        return KeyWatcherController(event_path="/dev/input/event2", mapping_provider=DictKeyMappingProvider(key_mappings))
    
    def get_device_name(self):
        return self.device_name
        
    def get_audio_system(self):
        return self.audio_player
    
    def get_core_name_overrides(self, core_name):
        return [core_name, core_name+"-64"]
    
    def supports_timezone_setting(self):
        return True

    def prompt_timezone_update(self):
        timezone_menu = TimezoneMenu()
        tz = timezone_menu.ask_user_for_timezone(timezone_menu.list_timezone_files('/usr/share/zoneinfo', verify_via_datetime=True))

        if (tz is not None):
            self.system_config.set_timezone(tz)
            self.apply_timezone(tz)

    def apply_timezone(self, timezone):
        with open("/storage/.cache/system_timezone", "w") as f:
            f.write(f"{timezone}\n")

        with open("/storage/.cache/timezone", "w") as f:
            f.write(f"TIMEZONE={timezone}\n")

        os.system("systemctl restart tz-data.service")

    def _set_volume(self, user_volume):
        from display.display import Display
        if(user_volume < 0):
            user_volume = 0
        elif(user_volume > 100):
            user_volume = 100
        volume = user_volume
        
        try:
            ProcessRunner.run(
                ["pactl", "--", "set-sink-volume", "@DEFAULT_SINK@", f"{volume}%"],
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

    def get_wifi_menu(self):
        return ConnmanWifiMenu()

    def get_new_wifi_scanner(self):
        return ConnmanWiFiScanner()