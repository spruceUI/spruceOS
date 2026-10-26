from pathlib import Path
import threading
from audio.audio_player_delegate_sdl2 import AudioPlayerDelegateSdl2
from controller.controller_inputs import ControllerInput
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller import KeyWatcherController
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.miyoo_trim_mapping_provider import MiyooTrimKeyMappingProvider
from devices.std_in_based_send_event_binary_helper import StdInBasedSendEventBinaryHelper
from devices.trimui.trim_ui_device import TrimUIDevice
from devices.utils.file_watcher import FileWatcher
from devices.utils.process_runner import ProcessRunner
from utils import throttle

from utils.config_copier import ConfigCopier
from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger

class TrimUIBrickPro(TrimUIDevice):
    
    TRIMUI_STOCK_CONFIG_LOCATION = "/mnt/UDISK/system.json"

    # The speaker amp stays on even when nothing plays and amplifies board
    # noise into an audible hiss (#1616; the real fix belongs in TrimUI's
    # driver, trimui/firmware_brickpro#5). When the menu has no sounds (button
    # clicks and background music both off) the amp is switched off; games and
    # apps get it back before PyUI hands off. Wired headphones are unaffected:
    # plugging them in mutes the speaker in hardware.
    SPEAKER_AMP_CONTROL = "name=HpSpeaker Switch"

    def __init__(self, device_name, main_ui_mode):
        self.device_name = device_name
        self.audio_player = AudioPlayerDelegateSdl2()
        script_dir = Path(__file__).resolve().parent
        source = script_dir / 'brick-system.json'
        self._load_system_config("/mnt/SDCARD/Saves/trim-ui-brick-pro-system.json", source)

        if(main_ui_mode):
            trim_stock_json_file = script_dir / 'stock/brick.json'
            ConfigCopier.ensure_config(TrimUIBrickPro.TRIMUI_STOCK_CONFIG_LOCATION, trim_stock_json_file)


            self.miyoo_games_file_parser = MiyooGamesFileParser()        
            threading.Thread(target=self.startup_init, daemon=True).start()
            self.config_watcher_thread, self.config_watcher_thread_stop_event = FileWatcher().start_file_watcher(
                "/mnt/SDCARD/Saves/trim-ui-brick-pro-system.json", self.on_system_config_changed, interval=0.2, repeat_trigger_for_mtime_granularity_issues=True)
            from controller.controller import Controller
            self.volume_key_watcher = KeyWatcher(TrimUIDevice.pad_event_path())
            Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
            volume_key_polling_thread = threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True)
            volume_key_polling_thread.start()
            self.power_key_watcher = KeyWatcher("/dev/input/event1")
            power_key_polling_thread = threading.Thread(target=self.power_key_watcher.poll_keyboard, daemon=True)
            power_key_polling_thread.start()
                
        super().__init__()
            

    def startup_init(self, include_wifi=True):
        self.sync_speaker_amp()
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
        return KeyWatcherController(event_path=TrimUIDevice.pad_event_path(), mapping_provider=MiyooTrimKeyMappingProvider(), event_format='llHHi')

    def supports_analog_calibration(self):
        return True

    def get_device_name(self):
        return self.device_name

    def get_device_names(self):
        names = [self.device_name, "TRIMUI_A133P"]
        return names
        
    def set_theme(self, theme_path: str):
        MiyooTrimCommon.set_theme(TrimUIBrickPro.TRIMUI_STOCK_CONFIG_LOCATION, theme_path)

    def get_audio_system(self):
        return self.audio_player
    
    def get_core_name_overrides(self, core_name):
        return [core_name, core_name+"-64"]    
    
    def might_require_surface_format_conversion(self):
        return True # RA save state images don't seem to load w/o conversion?
    
        
    def _menu_sounds_enabled(self):
        config = self.get_system_config()
        return config.play_button_press_sound() or config.play_bgm()

    def _set_speaker_amp(self, on):
        try:
            if not on:
                # Changing the volume powers the amp back on while the control
                # still reads "off", and the driver ignores a write that doesn't
                # change the value, so go through "on" to make "off" stick.
                ProcessRunner.run(["amixer", "-q", "-c", "0", "cset", self.SPEAKER_AMP_CONTROL, "on"], timeout=2)
            ProcessRunner.run(["amixer", "-q", "-c", "0", "cset", self.SPEAKER_AMP_CONTROL, "on" if on else "off"], timeout=2)
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Speaker amp switch failed: {e}")

    def sync_speaker_amp(self):
        """Speaker amp on if the menu plays sounds, off if it doesn't."""
        self._set_speaker_amp(self._menu_sounds_enabled())

    def menu_sound_settings_changed(self):
        self.sync_speaker_amp()

    # Games and apps run after PyUI hands off (and usually exits), so the amp
    # goes back on first; the next PyUI start syncs it to the settings again.
    def run_game(self, rom_info):
        self._set_speaker_amp(True)
        return super().run_game(rom_info)

    def run_app(self, folder, launch):
        self._set_speaker_amp(True)
        return super().run_app(folder, launch)

    def run_cmd(self, args, dir = None, is_power_cmd = False):
        self._set_speaker_amp(True)
        return super().run_cmd(args, dir, is_power_cmd)

    # The volume keys reach the firmware, which turns the amp back on; with the
    # menu silent, switch it off again once the change has gone through.
    def map_key(self, key_code):
        controller_input = super().map_key(key_code)
        if controller_input in (ControllerInput.VOLUME_UP, ControllerInput.VOLUME_DOWN) and not self._menu_sounds_enabled():
            threading.Timer(0.5, self.sync_speaker_amp).start()
        return controller_input

    def volume_up(self):
        StdInBasedSendEventBinaryHelper.send_key_down_and_up(TrimUIDevice.pad_event_path(),115)

    def volume_down(self):
        StdInBasedSendEventBinaryHelper.send_key_down_and_up(TrimUIDevice.pad_event_path(),114)
