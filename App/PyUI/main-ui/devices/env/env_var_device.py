

import shlex
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
from controller.key_watcher_controller import AxisKeyMappingProvider, DictKeyMappingProvider, HorizontalStickAxis, KeyWatcherController, VerticalStickAxis
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


# The launcher cannot start without these; every other variable is optional.
REQUIRED_ENV_VARS = (
    # Configs
    "DEFAULT_CFG_PATH", "SYSTEM_CFG_PATH", "PYUI_DEVICE_NAMES", 
    # Paths
    "ROMS_PATH", "FAVORITES_PATH", "RECENTS_PATH", "APPS_CONFIG_PATH", "COLLECTIONS_PATH", "STATE_PATH",
    # Screen
    "SCREEN_WIDTH", "SCREEN_HEIGHT", "SCREEN_ROTATION",
    # Controller
    "CONTROLLER_EVENT_PATH", "CONTROLLER_KEY_MAPPINGS", "CONTROLLER_EVENT_FORMAT",
    # Commands
    "POWER_OFF_CMD", 
    
)

class EnvVarDevice(DeviceCommon):
    def __init__(self, main_ui_mode):
        missing = [name for name in REQUIRED_ENV_VARS if not os.environ.get(name)]
        if missing:
            raise RuntimeError(f"EnvVarDevice needs these environment variables: {', '.join(missing)}")

        audio_player_env_var = os.environ.get("AUDIO_PLAYER", "")

        if audio_player_env_var == "SDL2":
            self.audio_player = AudioPlayerDelegateSdl2()
        elif audio_player_env_var == "OSS":
            self.audio_player = AudioPlayerOss()
        else:
            self.audio_player = AudioPlayerNone()

        default_cfg_path = Path(os.environ["DEFAULT_CFG_PATH"])
        system_cfg_path = os.environ["SYSTEM_CFG_PATH"]
        legacy_cfg_path = os.environ.get("LEGACY_CFG_PATH")
        if legacy_cfg_path and not self._is_usable_config(system_cfg_path) and self._is_usable_config(legacy_cfg_path):
            default_cfg_path = Path(legacy_cfg_path)

        self._load_system_config(system_cfg_path, default_cfg_path)
        self.battery_percent = 0
        self.status_errors_logged = set()

        # The watched key codes, read from the environment once.
        self.watched_key_codes = {}
        for name, controller_input in (("VOLUME_DOWN_KEYCODE", ControllerInput.VOLUME_DOWN),
                                       ("VOLUME_UP_KEYCODE", ControllerInput.VOLUME_UP),
                                       ("POWER_BUTTON_KEYCODE", ControllerInput.POWER_BUTTON)):
            if os.environ.get(name):
                self.watched_key_codes[int(os.environ[name])] = controller_input

        # A watcher per path variable that is set; an unset one means no watcher.
        self.volume_key_watcher = self._start_key_watcher("VOL_KEY_WATCHER_PATH", add_to_controller=True)
        self.power_key_watcher = self._start_key_watcher("POWER_KEY_WATCHER_PATH", add_to_controller=False)
        self.controller_watcher = self._start_key_watcher("CONTROLLER_KEY_WATCHER_PATH", add_to_controller=True)

        self.button_remapper = ButtonRemapper(self.system_config)

        if(main_ui_mode):
            # Done to try to account for external systems editting the config file
            self.config_watcher_thread, self.config_watcher_thread_stop_event = FileWatcher().start_file_watcher(
                system_cfg_path, self.on_system_config_changed, interval=0.2, repeat_trigger_for_mtime_granularity_issues=True)

        super().__init__()

        if(main_ui_mode and self.supports_touch()):
            self._start_touch_watcher()

    @staticmethod
    def _is_usable_config(path):
        # Same test ConfigCopier.ensure_config applies before deciding a config
        # needs seeding, so the two agree about what counts as "already there".
        try:
            path = Path(path)
            return path.exists() and path.stat().st_size > 0
        except OSError:
            return False

    def _start_touch_watcher(self):
        path = os.environ["TOUCH_EVENT_PATH"]
        if not os.path.exists(path):
            PyUiLogger.get_logger().warning(f"No touchscreen node at {path}; touch off")
            return
        from controller.touch_watcher import TouchWatcher
        self.touch_watcher = TouchWatcher(path, self)
        threading.Thread(target=self.touch_watcher.poll, daemon=True).start()

    def _start_key_watcher(self, path_var, add_to_controller):
        path = os.environ.get(path_var)
        if not path:
            return None
        from controller.controller import Controller
        watcher = KeyWatcher(path)
        # The node would not open (KeyWatcher logs why), so no thread polls it.
        if watcher.fd is None:
            return None
        if add_to_controller:
            Controller.add_button_watcher(watcher.poll_keyboard)
        threading.Thread(target=watcher.poll_keyboard, daemon=True).start()
        return watcher

    # A *_CMD is split like a shell command line, so one script can serve several settings.
    def _cmd(self, cmd_var):
        cmd = os.environ.get(cmd_var)
        return shlex.split(cmd) if cmd else None

    def _run_setting_cmd(self, cmd_var, *args):
        cmd = self._cmd(cmd_var)
        if not cmd:
            return
        try:
            subprocess.run(cmd + [str(arg) for arg in args],
                           stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=10, check=False)
        except Exception as e:
            PyUiLogger.get_logger().error(f"{cmd_var} failed: {e}")

    # A status comes from the file named in path_var when it is set, else from cmd_var's output.
    def _read_status(self, path_var, cmd_var):
        path = os.environ.get(path_var)
        if path:
            return Path(path).read_text().strip()
        cmd = self._cmd(cmd_var)
        if not cmd:
            return None
        return subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              text=True, timeout=5, check=False).stdout.strip()

    # Each kind of status failure is logged once.
    def _log_status_error(self, status, error):
        if status not in self.status_errors_logged:
            self.status_errors_logged.add(status)
            PyUiLogger.get_logger().warning(f"Could not read {status}: {error}")

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

    # Unset or empty: no reboot command (None).
    def reboot_cmd(self):
        return os.environ.get("REBOOT_CMD") or None

    def get_fw_version(self):
        return os.environ.get("FW_VERSION", "UNKNOWN")
        
    def _set_brightness_to_config(self):
        self._run_setting_cmd("BRIGHTNESS_CMD", self.system_config.brightness)

    def _set_lumination_to_config(self):
        self._run_setting_cmd("BACKLIGHT_CMD", self.system_config.backlight)

    def _set_contrast_to_config(self):
        self._run_setting_cmd("CONTRAST_CMD", self.system_config.contrast)

    def _set_saturation_to_config(self):
        self._run_setting_cmd("SATURATION_CMD", self.system_config.saturation)

    def _set_hue_to_config(self):
        self._run_setting_cmd("HUE_CMD", self.system_config.hue)

    def get_volume(self):
        return self.system_config.get_volume()
    
    def prompt_power_down(self):
        DeviceCommon.prompt_power_down(self)
        
    def volume_up(self):
        self._run_setting_cmd("VOL_UP_CMD")

    def volume_down(self):
        self._run_setting_cmd("VOL_DOWN_CMD")

    def special_input(self, controller_input, length_in_seconds):
        pass # do not do for env based devicess

    def is_wifi_enabled(self):
        return self.system_config.is_wifi_enabled()

    # "1" (a USB online node), Charging or Full counts as charging.
    @throttle.limit_refresh(5, background=True)
    def get_charge_status(self):
        try:
            status = self._read_status("CHARGE_STATUS_PATH", "CHARGE_STATUS_CMD")
        except Exception as e:
            self._log_status_error("the charge status", e)
            return ChargeStatus.DISCONNECTED
        if status and status.lower() in ("1", "charging", "full"):
            return ChargeStatus.CHARGING
        return ChargeStatus.DISCONNECTED

    # A failed read keeps the last good percentage.
    @throttle.limit_refresh(15, background=True)
    def get_battery_percent(self):
        try:
            percent = self._read_status("BATTERY_PERCENT_PATH", "BATTERY_PERCENT_CMD")
            if percent is not None:
                self.battery_percent = int(percent)
        except Exception as e:
            self._log_status_error("the battery percentage", e)
        return self.battery_percent

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

    def supports_touch(self):
        return bool(os.environ.get("TOUCH_EVENT_PATH"))

    def remap_buttons(self):
        self.button_remapper.remap_buttons()

    def supports_wifi(self):
        if os.environ.get("SUPPORTS_WIFI"):
            return os.environ["SUPPORTS_WIFI"].lower() == "true"
        return self._check_wifi_support()

    # The command's answer is cached for 30 s.
    @throttle.limit_refresh(30, background=True)
    def _check_wifi_support(self):
        cmd = self._cmd("CHECK_WIFI_SUPPORT_CMD")
        if not cmd:
            return False
        try:
            return subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                  timeout=10, check=False).returncode == 0
        except Exception as e:
            self._log_status_error("WiFi support", e)
            return False

    def get_roms_dir(self):
        return os.environ["ROMS_PATH"]

    def output_screen_width(self):
        if self.should_scale_screen():
            return int(os.environ.get("OUTPUT_SCREEN_WIDTH", self.screen_width()))
        else:
            return self.screen_width()

    def output_screen_height(self):
        if self.should_scale_screen():
            return int(os.environ.get("OUTPUT_SCREEN_HEIGHT", self.screen_height()))
        else:
            return self.screen_height()

    def get_scale_factor(self):
        if self.is_hdmi_connected():
            return float(os.environ.get("HDMI_SCALE_FACTOR", 1.0))
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

        # STICK_INVERT_X/Y flip the directions, for sticks whose axes run the other way.
        invert_x = os.environ.get("STICK_INVERT_X", "false").lower() == "true"
        invert_y = os.environ.get("STICK_INVERT_Y", "false").lower() == "true"

        def horizontal(left, right):
            return HorizontalStickAxis(right, left) if invert_x else HorizontalStickAxis(left, right)

        def vertical(up, down):
            return VerticalStickAxis(down, up) if invert_y else VerticalStickAxis(up, down)

        stick_axes = {}

        if "LEFT_STICK_X_AXIS" in os.environ:
            stick_axes[int(os.environ["LEFT_STICK_X_AXIS"])] = horizontal(
                ControllerInput.LEFT_STICK_LEFT,
                ControllerInput.LEFT_STICK_RIGHT,
            )

        if "LEFT_STICK_Y_AXIS" in os.environ:
            stick_axes[int(os.environ["LEFT_STICK_Y_AXIS"])] = vertical(
                ControllerInput.LEFT_STICK_UP,
                ControllerInput.LEFT_STICK_DOWN,
            )

        if "RIGHT_STICK_X_AXIS" in os.environ:
            stick_axes[int(os.environ["RIGHT_STICK_X_AXIS"])] = horizontal(
                ControllerInput.RIGHT_STICK_LEFT,
                ControllerInput.RIGHT_STICK_RIGHT,
            )

        if "RIGHT_STICK_Y_AXIS" in os.environ:
            stick_axes[int(os.environ["RIGHT_STICK_Y_AXIS"])] = vertical(
                ControllerInput.RIGHT_STICK_UP,
                ControllerInput.RIGHT_STICK_DOWN,
            )

        if "STICK_DEADZONE" in os.environ:
            return KeyWatcherController(
                event_path=os.environ["CONTROLLER_EVENT_PATH"],
                mapping_provider=AxisKeyMappingProvider(
                    key_mappings,
                    stick_axes,
                    int(os.environ.get("STICK_DEADZONE")),
                ),
                event_format=os.environ.get("CONTROLLER_EVENT_FORMAT"),
            )
        else:
            return KeyWatcherController(
                event_path=os.environ["CONTROLLER_EVENT_PATH"],
                mapping_provider=DictKeyMappingProvider(key_mappings),
                event_format=os.environ.get("CONTROLLER_EVENT_FORMAT"),
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

    @throttle.limit_refresh(5, background=True)
    def is_hdmi_connected(self):
        cmd = self._cmd("HDMI_STATUS_CMD")
        if not cmd:
            return False

        try:
            result = subprocess.run(
                cmd,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
                check=False,
            )
            return result.returncode == 0
        except Exception as e:
            self._log_status_error("the HDMI status", e)
            return False

    def map_key(self, key_code):
        if key_code in self.watched_key_codes:
            return self.watched_key_codes[key_code]

        PyUiLogger.get_logger().debug(f"Unrecognized keycode {key_code}")
        return None

    # Without all three variables the framebuffer calls do nothing.
    def _framebuffer(self):
        names = ("FRAMEBUFFER_DEVICE", "FRAMEBUFFER_BACKUP_PATH", "FRAMEBUFFER_BLOCK_SIZE")
        values = [os.environ.get(name) for name in names]
        return values if all(values) else None

    def capture_framebuffer(self):
        framebuffer = self._framebuffer()
        if framebuffer:
            device, backup_path, block_size = framebuffer
            ProcessRunner.run(["dd", f"if={device}", f"of={backup_path}", f"bs={block_size}"])

    def restore_framebuffer(self):
        framebuffer = self._framebuffer()
        if framebuffer:
            device, backup_path, block_size = framebuffer
            ProcessRunner.run(["dd", f"if={backup_path}", f"of={device}", f"bs={block_size}"])

    def clear_framebuffer(self):
        framebuffer = self._framebuffer()
        if framebuffer:
            device, _, block_size = framebuffer
            ProcessRunner.run(["dd", "if=/dev/zero", f"of={device}", f"bs={block_size}"])

    def get_image_utils(self):
        return FfmpegImageUtils()

    def get_device_name(self):
        return "ignored" # Needs to be refactored out

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

    def might_require_surface_format_conversion(self):
        return os.environ.get("REQUIRES_SURFACE_FORMAT_CONVERSION", "false").lower() == "true"

    # Frees the image cache once available memory drops below this many MB.
    @throttle.limit_refresh(1)
    def post_present_operations(self):
        threshold_mb = os.environ.get("CLEAR_DISPLAY_CACHE_BELOW_MB")
        if threshold_mb:
            self.clear_display_cache_if_memory_full("MemAvailable", int(threshold_mb))

    def screen_width(self):
        return int(os.environ["SCREEN_WIDTH"])
    
    def screen_height(self):
        return int(os.environ["SCREEN_HEIGHT"])
        
    def screen_rotation(self):
        return int(os.environ["SCREEN_ROTATION"])

    def supports_image_resizing(self):
        return os.environ.get("HAS_FFMPEG", "false").lower() == "true"
