import subprocess
import json
import os
from pathlib import Path
import threading
import time
from audio.audio_player_delegate_sdl2 import AudioPlayerDelegateSdl2
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller import DictKeyMappingProvider, KeyWatcherController
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo.system_config import SystemConfig
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.trimui.trim_ui_device import TrimUIDevice
from devices.miyoo_trim_mapping_provider import MiyooTrimKeyMappingProvider
from devices.utils.file_watcher import FileWatcher
from devices.utils.process_runner import ProcessRunner
from display.display import Display
from utils import throttle
from utils.config_copier import ConfigCopier

from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from asyncio import sleep

class TrimUISmartProS(TrimUIDevice):
    TRIMUI_STOCK_CONFIG_LOCATION = "/mnt/UDISK/system.json"

    def __init__(self, device_name,main_ui_mode):
        self.device_name = device_name
        self.audio_player = AudioPlayerDelegateSdl2()

        script_dir = Path(__file__).resolve().parent
        source = script_dir / 'brick-system.json'
        self._load_system_config("/mnt/SDCARD/Saves/trim-ui-smart-pro-s-system.json", source)
        self.mainui_volume = 0

        if(main_ui_mode):
            self.on_mainui_config_change()
            trim_stock_json_file = script_dir / 'stock/brick.json'
            ConfigCopier.ensure_config(TrimUISmartProS.TRIMUI_STOCK_CONFIG_LOCATION, trim_stock_json_file)

            self.mainui_config_thread, self.mainui_config_thread_stop_event = FileWatcher().start_file_watcher(
                TrimUISmartProS.TRIMUI_STOCK_CONFIG_LOCATION, self.on_mainui_config_change, interval=0.2, repeat_trigger_for_mtime_granularity_issues=True)

            self.miyoo_games_file_parser = MiyooGamesFileParser()        
            self.ensure_wpa_supplicant_conf()
            threading.Thread(target=self.monitor_wifi, daemon=True).start()
            threading.Thread(target=self.startup_init, daemon=True).start()
            if(PyUiConfig.enable_button_watchers()):
                from controller.controller import Controller
                #/dev/miyooio if we want to get rid of miyoo_inputd
                # debug in terminal: hexdump  /dev/miyooio
                self.volume_key_watcher = KeyWatcher("/dev/input/event0")
                Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
                volume_key_polling_thread = threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True)
                volume_key_polling_thread.start()
                self.power_key_watcher = KeyWatcher("/dev/input/event0")
                power_key_polling_thread = threading.Thread(target=self.power_key_watcher.poll_keyboard, daemon=True)
                power_key_polling_thread.start()
                
            config_volume = self.system_config.get_volume()
            self._set_volume(config_volume)
        super().__init__()

    def startup_init(self, include_wifi=True):
        self._set_lumination_to_config()
        config_volume = self.system_config.get_volume()
        self._set_volume(config_volume)

    def _set_volume(self, user_volume):
        # Investigate sending volume key
        pass

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
        return KeyWatcherController(event_path="/dev/input/event4", mapping_provider=MiyooTrimKeyMappingProvider(), event_format='llHHi')
    
    def get_device_name(self):
        return self.device_name
        
    def set_theme(self, theme_path: str):
        MiyooTrimCommon.set_theme(TrimUISmartProS.TRIMUI_STOCK_CONFIG_LOCATION, theme_path)

    def get_audio_system(self):
        return self.audio_player
    
    def get_core_name_overrides(self, core_name):
        return [core_name, core_name+"-64"]

    def get_volume(self):
        try:
            return self.mainui_volume * 5
        except:
            return 0
        
    def on_mainui_config_change(self):
        path = TrimUISmartProS.TRIMUI_STOCK_CONFIG_LOCATION
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

    def _set_lumination_to_config(self):
        val = self.map_backlight_from_10_to_full_255(self.system_config.backlight)
        try:
            with open("/sys/class/backlight/backlight0/brightness", "w") as f:
                f.write(str(val))
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error setting backlight: {e}")

    def volume_up(self):
        try:
            proc = subprocess.Popen(
                ["sendevent", "/dev/input/event0"],
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
                ["sendevent", "/dev/input/event0"],
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

    def change_volume(self, amount):
        PyUiLogger.get_logger().debug(f"Changing volume by {amount}")
        self.system_config.reload_config()
        volume = self.get_volume() + amount
        if(volume < 0):
            volume = 0
        elif(volume > 100):
            volume = 100
        if(amount > 0):
            self.volume_up()
        else:
            self.volume_down()
        sleep(0.1)
        self.on_mainui_config_change()

    def enable_bluetooth(self):
        if(not self.is_bluetooth_enabled()):
            subprocess.Popen(['./bluetoothd',"-f","/etc/bluetooth/main.conf"],
                            cwd='/usr/libexec/bluetooth/',
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
        self.system_config.set_bluetooth(1)

    def _signal_osd_quit(self):
        os.makedirs("/tmp/trimui_osd", exist_ok=True)
        open("/tmp/trimui_osd/osdd_quit", "a").close()

    def _wpa_supplicant_quit(self):
        ProcessRunner.run(["killall", "wpa_supplicant"])  

    def _prepare_for_power_action(self):
        self._signal_osd_quit()
        self._wpa_supplicant_quit()
        time.sleep(1)

    def power_off(self):
        Display.display_message("Powering off...")
        self._prepare_for_power_action()
        time.sleep(1)
        self.run_cmd([self.power_off_cmd()])
        # So we dont update the display while shutting down
        time.sleep(10)


    def reboot(self):
        Display.display_message("Rebooting...")
        self._prepare_for_power_action()
        time.sleep(1)
        self.run_cmd([self.reboot_cmd()])
        # So we dont update the display while rebooting
        time.sleep(10)
