import os
import subprocess
from pathlib import Path

from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from audio.audio_player_delegate_sdl2 import AudioPlayerDelegateSdl2
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher_controller import KeyWatcherController
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.charge.charge_status import ChargeStatus
from devices.darkmoss.darkmoss_common import DarkmossPanelCalibration, darkmoss_fw_version
from devices.darkmoss.darkmoss_key_mapping_provider import DarkmossKeyMappingProvider
from devices.device_common import DeviceCommon
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo_trim_common import MiyooTrimCommon
from display.display import Display
from games.utils.device_specific.miyoo_trim_game_system_utils import MiyooTrimGameSystemUtils
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from menus.settings.button_remapper import ButtonRemapper
from utils import throttle
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig


class DarkmossDevice(DeviceCommon):
    """Base for every device running dArkMoss, spruce on TF2."""

    JOYPAD_NODE = None
    SYSTEM_JSON = None
    SYSTEM_JSON_DEFAULT = None
    MENU_KEY = None
    SELECT_KEY = 314
    START_KEY = 315
    BATTERYPLUS_PERCENT_FILE = None
    # volumeCmd/backlightCmd scripts, for bases with no softvol Master or another backlight range.
    VOLUME_BACKLIGHT_CMDS = False
    BACKLIGHT_TABLE = None
    PANEL_CALIBRATION = True

    def __init__(self, device_name):
        self.device_name = device_name
        self.audio_player = AudioPlayerDelegateSdl2()
        self._load_system_config(self.SYSTEM_JSON, Path(__file__).resolve().parent / self.SYSTEM_JSON_DEFAULT)
        self.panel_calibration = DarkmossPanelCalibration(self.system_config)
        self.button_remapper = ButtonRemapper(self.system_config)
        self.game_utils = MiyooTrimGameSystemUtils()
        self.miyoo_games_file_parser = MiyooGamesFileParser()
        DeviceCommon.__init__(self)
        self._start_volume_watcher()

    def wants_gles_context(self):
        # The Mali blobs offer no desktop GL config.
        return True

    # The shell owns the volume keys; PyUI reflects the config it writes.
    def _start_volume_watcher(self):
        from devices.utils.file_watcher import FileWatcher
        self.config_watcher_thread, self.config_watcher_thread_stop_event = FileWatcher().start_file_watcher(
            self.SYSTEM_JSON, self.on_system_config_changed,
            interval=0.2, repeat_trigger_for_mtime_granularity_issues=True)

    def on_system_config_changed(self):
        old_volume = self.system_config.get_volume()
        self.system_config.reload_config()
        new_volume = self.system_config.get_volume()
        if old_volume != new_volume:
            Display.volume_changed(new_volume)

    def _set_volume(self, volume):
        if self.VOLUME_BACKLIGHT_CMDS:
            return self._set_volume_via_cmd(volume)
        # change_volume passes 0-100, which maps straight to the softvol Master.
        pct = max(0, min(100, int(volume)))
        try:
            subprocess.run(["amixer", "-M", "-q", "sset", "Master", f"{pct}%"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            PyUiLogger.get_logger().error(f"{self.device_name}: _set_volume failed: {e}")
        return volume

    def _set_volume_via_cmd(self, volume):
        # volumeCmd takes the 0-20 level PyUI has saved.
        level = max(0, min(20, int(volume) // 5))
        volume_cmd = PyUiConfig.get_volume_cmd()
        if volume_cmd and os.path.exists(volume_cmd):
            try:
                subprocess.run([volume_cmd, str(level)],
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               timeout=10, check=False)
            except Exception as e:
                PyUiLogger.get_logger().error(f"{self.device_name}: volume command failed: {e}")
        return volume

    def _resolve_joypad(self):
        if os.path.exists(self.JOYPAD_NODE):
            PyUiLogger.get_logger().info(f"{self.device_name}: joypad at {self.JOYPAD_NODE}")
        else:
            PyUiLogger.get_logger().error(
                f"{self.device_name}: no joypad node at {self.JOYPAD_NODE}, controls will not respond"
            )
        return self.JOYPAD_NODE

    def _button_mappings(self):
        key_mappings = {}

        def bind(code, control):
            key_mappings[KeyEvent(1, code, 1)] = [InputResult(control, KeyState.PRESS)]
            key_mappings[KeyEvent(1, code, 0)] = [InputResult(control, KeyState.RELEASE)]

        bind(305, ControllerInput.A)          # BTN_EAST
        bind(304, ControllerInput.B)          # BTN_SOUTH
        bind(307, ControllerInput.X)          # BTN_NORTH
        bind(308, ControllerInput.Y)          # BTN_WEST

        bind(310, ControllerInput.L1)
        bind(311, ControllerInput.R1)
        bind(312, ControllerInput.L2)
        bind(313, ControllerInput.R2)

        bind(self.START_KEY, ControllerInput.START)
        bind(self.SELECT_KEY, ControllerInput.SELECT)
        if self.MENU_KEY is not None:
            bind(self.MENU_KEY, ControllerInput.MENU)

        bind(544, ControllerInput.DPAD_UP)
        bind(545, ControllerInput.DPAD_DOWN)
        bind(546, ControllerInput.DPAD_LEFT)
        bind(547, ControllerInput.DPAD_RIGHT)

        return key_mappings

    # Stick clicks (317/318) are resolved in the provider: one can be the menu button.
    def _mapping_provider(self, key_mappings):
        return DarkmossKeyMappingProvider(key_mappings)

    def get_controller_interface(self):
        return KeyWatcherController(
            # Signed: the default unsigned format reads negative axis values as huge positives.
            event_format="llHHi",
            event_path=self._resolve_joypad(),
            mapping_provider=self._mapping_provider(self._button_mappings()),
        )

    def run_game(self, rom_info: RomInfo) -> subprocess.Popen:
        return MiyooTrimCommon.run_game(self, rom_info)

    def run_app(self, folder, launch):
        return MiyooTrimCommon.run_app(self, folder, launch)

    def run_cmd(self, args, dir = None, is_power_cmd = False):
        PyUiLogger.get_logger().debug(f"About to launch app {args} from dir {dir}")
        subprocess.run(args, cwd = dir)

    def supports_wifi(self):
        return True

    def is_wifi_enabled(self):
        return self.system_config.is_wifi_enabled()

    def get_device_name(self):
        return self.device_name

    def get_device_names(self):
        return [self.device_name, "DARKMOSS"]

    def screen_rotation(self):
        return 0

    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        if self.BATTERYPLUS_PERCENT_FILE:
            try:
                with open(self.BATTERYPLUS_PERCENT_FILE, "r") as f:
                    percent = int(f.read().strip())
                if 0 <= percent <= 100:
                    return percent
            except (OSError, ValueError):
                pass
        try:
            with open("/sys/class/power_supply/battery/capacity", "r") as f:
                return int(f.read().strip())
        except (OSError, ValueError):
            return 0

    @throttle.limit_refresh(5)
    def get_charge_status(self):
        try:
            with open("/sys/class/power_supply/battery/status", "r") as f:
                status = f.read().strip()
        except OSError:
            return ChargeStatus.DISCONNECTED

        return ChargeStatus.CHARGING if status == "Charging" else ChargeStatus.DISCONNECTED

    def is_hdmi_connected(self):
        try:
            with open("/sys/class/extcon/hdmi/cable.0/state", "r") as f:
                return f.read().strip() == "1"
        except OSError:
            return False

    def sleep(self):
        pass

    def get_fw_version(self):
        return darkmoss_fw_version() or "Unknown"

    def should_scale_screen(self):
        return self.is_hdmi_connected()

    # Through systemd so TF2 is unmounted cleanly.
    def power_off_cmd(self):
        return "systemctl poweroff"

    def reboot_cmd(self):
        return "systemctl reboot"

    def _set_lumination_to_config(self):
        level = max(0, min(10, int(self.system_config.backlight)))
        if self.VOLUME_BACKLIGHT_CMDS:
            self._set_lumination_via_cmd(level)
            return
        try:
            with open("/sys/class/backlight/backlight/brightness", "w") as f:
                f.write(str(self.BACKLIGHT_TABLE[level]))
        except OSError as e:
            PyUiLogger.get_logger().error(f"{self.device_name}: backlight write failed: {e}")

    def _set_lumination_via_cmd(self, level):
        # Panel only: PyUI saves the level itself, and the screensaver dim must not be saved.
        backlight_cmd = PyUiConfig.get_backlight_cmd()
        if not backlight_cmd or not os.path.exists(backlight_cmd):
            return
        try:
            subprocess.run([backlight_cmd, str(level)],
                           stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=10, check=False)
        except Exception as e:
            PyUiLogger.get_logger().error(f"{self.device_name}: backlight command failed: {e}")

    def _set_brightness_to_config(self):
        self.panel_calibration.apply("brightness")

    def _set_contrast_to_config(self):
        self.panel_calibration.apply("contrast")

    def _set_saturation_to_config(self):
        self.panel_calibration.apply("saturation")

    def _set_hue_to_config(self):
        self.panel_calibration.apply("hue")

    def supports_brightness_calibration(self):
        return self.PANEL_CALIBRATION and self.panel_calibration.supports("brightness")

    def supports_contrast_calibration(self):
        return self.PANEL_CALIBRATION and self.panel_calibration.supports("contrast")

    def supports_saturation_calibration(self):
        return self.PANEL_CALIBRATION and self.panel_calibration.supports("saturation")

    def supports_hue_calibration(self):
        return self.PANEL_CALIBRATION and self.panel_calibration.supports("hue")

    def startup_init(self, include_wifi=True):
        self.panel_calibration.apply_all()

    def get_volume(self):
        return self.system_config.get_volume()

    def map_digital_input(self, sdl_input):
        return None

    def map_analog_input(self, sdl_axis, sdl_value):
        return None

    def prompt_power_down(self):
        DeviceCommon.prompt_power_down(self)

    def change_volume(self, amount):
        self.system_config.reload_config()
        volume = max(0, min(100, self.get_volume() + amount))
        self._set_volume(volume)
        self.system_config.set_volume(volume)
        self.system_config.save_config()
        Display.volume_changed(self.get_volume())

    def volume_up(self):
        self.change_volume(+5)

    def volume_down(self):
        self.change_volume(-5)

    def special_input(self, controller_input, length_in_seconds):
        if(PyUiConfig.enable_button_watchers()):
            if(ControllerInput.POWER_BUTTON == controller_input):
                if(length_in_seconds < 1):
                    self.sleep()
                else:
                    self.prompt_power_down()
            elif(ControllerInput.VOLUME_UP == controller_input):
                self.change_volume(5)
            elif(ControllerInput.VOLUME_DOWN == controller_input):
                self.change_volume(-5)

    def get_app_finder(self):
        return MiyooAppFinder()

    def parse_favorites(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_favorites()

    def parse_recents(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_recents()

    def perform_startup_tasks(self):
        pass

    def get_audio_system(self):
        return self.audio_player

    def get_favorites_path(self):
        return "/mnt/SDCARD/Saves/pyui-favorites.json"

    def get_recents_path(self):
        return "/mnt/SDCARD/Saves/pyui-recents.json"

    def get_apps_config_path(self):
        return "/mnt/SDCARD/Saves/pyui-apps.json"

    def get_collections_path(self):
        return "/mnt/SDCARD/Collections/"

    def launch_stock_os_menu(self):
        os._exit(0)

    def get_state_path(self):
        return "/mnt/SDCARD/pyui/config/pyui-state.json"

    def calibrate_sticks(self):
        pass

    def supports_analog_calibration(self):
        return False

    def supports_image_resizing(self):
        return True

    def remap_buttons(self):
        self.button_remapper.remap_buttons()

    def get_roms_dir(self):
        return "/mnt/SDCARD/Roms/"

    def output_screen_width(self):
        if(self.should_scale_screen()):
            return 1920
        else:
            return self.screen_width()

    def output_screen_height(self):
        if(self.should_scale_screen()):
            return 1080
        else:
            return self.screen_height()

    def get_scale_factor(self):
        if(self.is_hdmi_connected()):
            return 2.25
        else:
            return 1

    def get_game_system_utils(self):
        return self.game_utils

    def get_extra_settings_options(self):
        return []

    def take_snapshot(self, path):
        return None

    def get_save_state_image(self, rom_info: RomInfo):
        return self.get_game_system_utils().get_save_state_image(rom_info)

    def keep_running_on_error(self):
        return False

    def perform_sdcard_ro_check(self):
        PyUiLogger.get_logger().info(f"{self.device_name}: not checking read-only SD card status.")
