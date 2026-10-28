

import subprocess
import json
import os
from pathlib import Path
import threading

from audio.audio_player_delegate_sdl2 import AudioPlayerDelegateSdl2
from audio.audio_player_none import AudioPlayerNone
from audio.audio_player_oss import AudioPlayerOss
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller import AxisKeyMappingProvider, HorizontalStickAxis, KeyWatcherController, VerticalStickAxis
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.charge.charge_status import ChargeStatus
from devices.device_common import DeviceCommon
from devices.utils.file_watcher import FileWatcher
from devices.utils.process_runner import ProcessRunner
from display.display import Display
from menus.games.utils.rom_info import RomInfo
from menus.settings.button_remapper import ButtonRemapper
from utils import throttle
from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger


class EnvVarDevice(DeviceCommon):
    def __init__(self, main_ui_mode):
        audio_player_env_var = os.environ.get("AUDIO_PLAYER", "")

        if audio_player_env_var == "SDL2":
            self.audio_player = AudioPlayerDelegateSdl2()
        elif audio_player_env_var == "OSS":
            self.audio_player = AudioPlayerOss()
        else:
            self.audio_player = AudioPlayerNone()
    
        self.has_rgb_rings = os.getenv("HAS_RGB_RINGS", "false") == "true"
        self.has_lid_wake = os.getenv("HAS_LID_WAKE", "false") == "true"
        default_cfg_path = Path(os.environ["DEFAULT_CFG_PATH"])
        system_cfg_path = os.environ["SYSTEM_CFG_PATH"]
        legacy_cfg_path = Path(os.environ["LEGACY_CFG_PATH"])
        if not self._is_usable_config(system_cfg_path) and self._is_usable_config(legacy_cfg_path):
            default_cfg_path = legacy_cfg_path

        self._load_system_config(system_cfg_path, default_cfg_path)

        from controller.controller import Controller
        self.volume_key_watcher = KeyWatcher(os.environ["VOL_KEY_WATCHER_PATH"])        
        Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
        volume_key_polling_thread = threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True)
        volume_key_polling_thread.start()
        self.power_key_watcher = KeyWatcher(os.environ["POWER_KEY_WATCHER_PATH"])  
        power_key_polling_thread = threading.Thread(target=self.power_key_watcher.poll_keyboard, daemon=True)
        power_key_polling_thread.start()
        self.controller_watcher = KeyWatcher(os.environ["CONTROLLER_KEY_WATCHER_PATH"])
        Controller.add_button_watcher(self.controller_watcher.poll_keyboard)
        controller_watching_thread = threading.Thread(target=self.controller_watcher.poll_keyboard, daemon=True)
        controller_watching_thread.start()

        self.button_remapper = ButtonRemapper(self.system_config)

        if(main_ui_mode):
            # Done to try to account for external systems editting the config file
            self.config_watcher_thread, self.config_watcher_thread_stop_event = FileWatcher().start_file_watcher(
                system_cfg_path, self.on_system_config_changed, interval=0.2, repeat_trigger_for_mtime_granularity_issues=True)

        super().__init__()

    @staticmethod
    def _is_usable_config(path):
        # Same test ConfigCopier.ensure_config applies before deciding a config
        # needs seeding, so the two agree about what counts as "already there".
        try:
            path = Path(path)
            return path.exists() and path.stat().st_size > 0
        except OSError:
            return False

    def on_system_config_changed(self):
        old_volume = self.system_config.get_volume()
        self.system_config.reload_config()
        new_volume = self.system_config.get_volume()
        if(old_volume != new_volume):
            Display.volume_changed(new_volume)

    def sleep(self):
        pass 

    def should_scale_screen(self):
        return self.is_hdmi_connected()

    def power_off_cmd(self):
        return os.environ["POWER_OFF_CMD"]
    
    def reboot_cmd(self):
        return os.environ["REBOOT_CMD"]

    def get_fw_version(self):
        return os.environ["FW_VERSION"]

    def _set_brightness_to_config(self):
        cmd = os.environ.get("BRIGHTNESS_CMD")
        if cmd:
            subprocess.run([cmd, str(self.system_config.brightness)],
                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        timeout=10, check=False)        
                              
    def _set_lumination_to_config(self):
        cmd = os.environ.get("BACKLIGHT_CMD")
        if cmd:
            subprocess.run([cmd, str(self.system_config.backlight)],
                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        timeout=10, check=False)        

    def _set_contrast_to_config(self):
        cmd = os.environ.get("CONTRAST_CMD")
        if cmd:
            subprocess.run([cmd, str(self.system_config.contrast)],
                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        timeout=10, check=False)        
    
    def _set_saturation_to_config(self): 
        cmd = os.environ.get("SATURATION_CMD")
        if cmd:
            subprocess.run([cmd, str(self.system_config.saturation)],
                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        timeout=10, check=False)        


    def _set_hue_to_config(self):
        cmd = os.environ.get("HUE_CMD")
        if cmd:
            subprocess.run([cmd, str(self.system_config.hue)],
                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        timeout=10, check=False)        

    def get_volume(self):
        return self.system_config.get_volume()
    
    def prompt_power_down(self):
        DeviceCommon.prompt_power_down(self)
        
    def volume_up(self):
        cmd = os.environ.get("VOL_UP_CMD")
        if cmd:
            subprocess.run([cmd],
                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        timeout=10, check=False)        

    def volume_down(self):
        cmd = os.environ.get("VOL_DOWN_CMD")
        if cmd:
            subprocess.run([cmd],
                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        timeout=10, check=False)        

    def special_input(self, controller_input, length_in_seconds):
        pass # do not do for env based devicess

    def is_wifi_enabled(self):
        return self.system_config.is_wifi_enabled()

    @throttle.limit_refresh(5)
    def get_charge_status(self):
        cmd = os.environ.get("CHARGE_STATUS_CMD")
        if not cmd:
            return ChargeStatus.DISCONNECTED

        try:
            result = subprocess.run(
                [cmd],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
                check=False,
            )
            if result.returncode == 0:
                return ChargeStatus.CHARGING
            return ChargeStatus.DISCONNECTED
        except:
            # Battery status command unavailable
            return ChargeStatus.DISCONNECTED        
        
    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        cmd = os.environ.get("BATTERY_PERCENT_CMD")
        if not cmd:
            return 0

        try:
            result = subprocess.run(
                [cmd],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=5,
                check=True,
            )
            return int(result.stdout.strip())
        except:
            return 0

    def perform_startup_tasks(self):
        pass

    def get_audio_system(self):
        return self.audio_player
    
    def launch_stock_os_menu(self):
        os._exit(0)

    def get_favorites_path(self):
        return os.environ["FAVORITES_PATH"]

    def get_recents_path(self):
        return os.environ["RECENTS_PATH"]

    def get_apps_config_path(self):
        return os.environ["APPS_CONFIG_PATH"]

    def get_collections_path(self):
        return os.environ["COLLECTIONS_PATH"]

    def get_state_path(self):
        return os.environ["STATE_PATH"]
    
    def supports_image_resizing(self):
        return os.environ.get("SUPPORTS_IMAGE_RESIZING", "false").lower() == "true"

    def remap_buttons(self):
        self.button_remapper.remap_buttons()

    def supports_wifi(self):
        cmd = os.environ.get("CHECK_WIFI_SUPPORT_CMD")
        if not cmd:
            return False

        try:
            result = subprocess.run(
                [cmd],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=10,
                check=False,
            )
            return result.returncode == 0
        except:
            return False    
        
    def get_roms_dir(self):
        return os.environ["ROMS_PATH"]

    def output_screen_width(self):
        if self.should_scale_screen():
            return int(os.environ["OUTPUT_SCREEN_WIDTH"])
        else:
            return self.screen_width()

    def output_screen_height(self):
        if self.should_scale_screen():
            return int(os.environ["OUTPUT_SCREEN_HEIGHT"])
        else:
            return self.screen_height()

    def get_scale_factor(self):
        if self.is_hdmi_connected():
            return float(os.environ["HDMI_SCALE_FACTOR"])
        else:
            return 1.0
        
    def get_game_system_utils(self):
        return self.game_utils
    
    def take_snapshot(self, path):
        return None
    
    def get_save_state_image(self, rom_info: RomInfo):
        return self.get_game_system_utils().get_save_state_image(rom_info)

    def supports_brightness_calibration(self):
        return bool(os.environ.get("BRIGHTNESS_CMD"))

    def supports_contrast_calibration(self):
        return bool(os.environ.get("CONTRAST_CMD"))

    def supports_saturation_calibration(self):
        return bool(os.environ.get("SATURATION_CMD"))

    def supports_hue_calibration(self):
        return bool(os.environ.get("HUE_CMD"))

    # Why is this in device?
    def keep_running_on_error(self):
        return False

    def get_controller_interface(self):
        mappings = json.loads(os.environ["CONTROLLER_KEY_MAPPINGS"])

        key_mappings = {
            KeyEvent(mapping["type"], mapping["code"], mapping["value"]): [
                InputResult(
                    ControllerInput[result["input"]],
                    KeyState[result["state"]],
                )
                for result in mapping["results"]
            ]
            for mapping in mappings
        }

        stick_axes = {}

        if "LEFT_STICK_X_AXIS" in os.environ:
            stick_axes[int(os.environ["LEFT_STICK_X_AXIS"])] = HorizontalStickAxis(
                ControllerInput.LEFT_STICK_LEFT,
                ControllerInput.LEFT_STICK_RIGHT,
            )

        if "LEFT_STICK_Y_AXIS" in os.environ:
            stick_axes[int(os.environ["LEFT_STICK_Y_AXIS"])] = VerticalStickAxis(
                ControllerInput.LEFT_STICK_UP,
                ControllerInput.LEFT_STICK_DOWN,
            )

        if "RIGHT_STICK_X_AXIS" in os.environ:
            stick_axes[int(os.environ["RIGHT_STICK_X_AXIS"])] = HorizontalStickAxis(
                ControllerInput.RIGHT_STICK_LEFT,
                ControllerInput.RIGHT_STICK_RIGHT,
            )

        if "RIGHT_STICK_Y_AXIS" in os.environ:
            stick_axes[int(os.environ["RIGHT_STICK_Y_AXIS"])] = VerticalStickAxis(
                ControllerInput.RIGHT_STICK_UP,
                ControllerInput.RIGHT_STICK_DOWN,
            )

        return KeyWatcherController(
            event_path=os.environ["CONTROLLER_EVENT_PATH"],
            mapping_provider=AxisKeyMappingProvider(
                key_mappings,
                stick_axes,
                int(os.environ["STICK_DEADZONE"]),
            ),
            event_format=os.environ["CONTROLLER_EVENT_FORMAT"],
        )

    def are_headphones_plugged_in(self):
        cmd = os.environ.get("HEADPHONES_STATUS_CMD")
        if not cmd:
            return False

        try:
            result = subprocess.run(
                [cmd],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
                check=False,
            )
            return result.returncode == 0
        except:
            return False        
        
    def is_lid_closed(self):
        path = os.environ.get("LID_STATUS_PATH")
        if not path:
            return False

        try:
            value = Path(path).read_text().strip()
            return value == os.environ["LID_CLOSED_VALUE"]
        except:
            return False

    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        cmd = os.environ.get("HDMI_STATUS_CMD")
        if not cmd:
            return False

        try:
            result = subprocess.run(
                [cmd],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
                check=False,
            )
            return result.returncode == 0
        except:
            return False
            
    def map_key(self, key_code):
        key_mappings = {
            int(os.environ["VOLUME_DOWN_KEYCODE"]): ControllerInput.VOLUME_DOWN,
            int(os.environ["VOLUME_UP_KEYCODE"]): ControllerInput.VOLUME_UP,
            int(os.environ["POWER_BUTTON_KEYCODE"]): ControllerInput.POWER_BUTTON,
        }

        if key_code in key_mappings:
            return key_mappings[key_code]

        PyUiLogger.get_logger().debug(f"Unrecognized keycode {key_code}")
        return None

    def capture_framebuffer(self):
        ProcessRunner.run([
            "dd",
            f"if={os.environ['FRAMEBUFFER_DEVICE']}",
            f"of={os.environ['FRAMEBUFFER_BACKUP_PATH']}",
            f"bs={os.environ['FRAMEBUFFER_BLOCK_SIZE']}",
        ])

    def restore_framebuffer(self):
        ProcessRunner.run([
            "dd",
            f"if={os.environ['FRAMEBUFFER_BACKUP_PATH']}",
            f"of={os.environ['FRAMEBUFFER_DEVICE']}",
            f"bs={os.environ['FRAMEBUFFER_BLOCK_SIZE']}",
        ])

    def clear_framebuffer(self):
        ProcessRunner.run([
            "dd",
            "if=/dev/zero",
            f"of={os.environ['FRAMEBUFFER_DEVICE']}",
            f"bs={os.environ['FRAMEBUFFER_BLOCK_SIZE']}",
        ])

    def get_image_utils(self):
        return FfmpegImageUtils()

    def get_device_name(self):
        return os.environ["PRIMARY_PYUI_DEVICE_NAME"]

    def get_device_names(self):
        return [
            name.strip()
            for name in os.environ["PYUI_DEVICE_NAMES"].split(",")
            if name.strip()
        ]

    def check_for_button_remap(self, input):
        return self.button_remapper.get_mappping(input)

    def uses_deinit_v2(self):
        return True

                   
    def screen_width(self):
        return int(os.environ["SCREEN_WIDTH"])
    
    def screen_height(self):
        return int(os.environ["SCREEN_HEIGHT"])
        
    def screen_rotation(self):
        return int(os.environ["SCREEN_ROTATION"])
