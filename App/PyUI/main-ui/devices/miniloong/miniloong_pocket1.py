import os
import subprocess
import sys
import threading
from pathlib import Path

from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher_controller import KeyWatcherController
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.charge.charge_status import ChargeStatus
from devices.darkmoss_common import DarkmossPanelCalibration, darkmoss_fw_version
from devices.device_common import DeviceCommon
from devices.miniloong.miniloong_key_mapping_provider import MiniloongKeyMappingProvider
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


class MiniloongPocket1(DeviceCommon):
    """Miniloong Pocket 1 (RK3566, Mali-G52) on dArkMoss.

    Shape follows the RGB30 class: same base OS, same retrogame_joypad driver,
    same Mali blob. The differences are the 960x720 panel (a portrait mode used
    in landscape, rendered at 1.5x), a real menu button, one stick, and the
    backlight table.
    """

    SYSTEM_JSON = "/mnt/SDCARD/App/PyUI/config/miniloong-system.json"
    JOYPAD_NODE = "/dev/input/by-path/platform-singleadc-joypad-event-joystick"

    # Backlight raw per 0..10 level, mirroring SYSTEM_BRIGHTNESS_0..10 in
    # spruce/scripts/platform/Miniloong.cfg. Measured 2026-09-04: the panel is
    # black at raw 60 and below; level 0 is the dimmest safe level.
    BACKLIGHT_TABLE = (70, 77, 83, 90, 96, 103, 109, 116, 122, 129, 135)
    BACKLIGHT_FLOOR = 70

    def __init__(self, device_name, main_ui_mode=True):
        self.device_name = device_name
        self.load_miniloong_system_json()
        self.panel_calibration = DarkmossPanelCalibration(self.system_config)
        self.button_remapper = ButtonRemapper(self.system_config)
        self.game_utils = MiyooTrimGameSystemUtils()
        self.miyoo_games_file_parser = MiyooGamesFileParser()
        DeviceCommon.__init__(self)
        if main_ui_mode:
            threading.Thread(target=self._set_lumination_to_config, daemon=True).start()
        self._start_volume_watcher()

    def wants_gles_context(self):
        return True

    # ---- config ----

    def load_miniloong_system_json(self):
        base_dir = os.path.abspath(sys.path[0])
        self.script_dir = os.path.join(base_dir, "devices", "miniloong")
        source = os.path.join(self.script_dir, "miniloong-system.json")
        self._load_system_config(self.SYSTEM_JSON, Path(source))

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

    # ---- input ----

    def _resolve_joypad(self):
        if os.path.exists(self.JOYPAD_NODE):
            PyUiLogger.get_logger().info(f"Miniloong: joypad at {self.JOYPAD_NODE}")
        else:
            PyUiLogger.get_logger().error("Miniloong: no singleadc joypad node found, controls will not respond")
        return self.JOYPAD_NODE

    def get_controller_interface(self):
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

        bind(315, ControllerInput.START)
        bind(314, ControllerInput.SELECT)
        bind(316, ControllerInput.MENU)       # BTN_MODE, a real button here
        bind(317, ControllerInput.L3)
        bind(318, ControllerInput.R3)

        bind(544, ControllerInput.DPAD_UP)
        bind(545, ControllerInput.DPAD_DOWN)
        bind(546, ControllerInput.DPAD_LEFT)
        bind(547, ControllerInput.DPAD_RIGHT)

        return KeyWatcherController(
            event_format="llHHi",
            event_path=self._resolve_joypad(),
            mapping_provider=MiniloongKeyMappingProvider(key_mappings),
        )

    def map_digital_input(self, sdl_input):
        return None

    def map_analog_input(self, sdl_axis, sdl_value):
        return None

    # ---- screen ----

    def get_device_name(self):
        return self.device_name

    def get_device_names(self):
        return [self.device_name, "DARKMOSS"]

    def screen_width(self):
        return 960

    def screen_height(self):
        return 720

    def screen_rotation(self):
        return 270

    def output_screen_width(self):
        if self.should_scale_screen():
            return 1920
        return int(self.screen_width() * 1.5)

    def output_screen_height(self):
        if self.should_scale_screen():
            return 1080
        return int(self.screen_height() * 1.5)

    # The panel is higher-DPI than the 960x720 base render.
    def get_scale_factor(self):
        return 2 if self.is_hdmi_connected() else 1.5

    def should_scale_screen(self):
        return self.is_hdmi_connected()

    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        try:
            with open("/sys/class/drm/card0-HDMI-A-1/status") as f:
                return f.read().strip().lower() == "connected"
        except OSError:
            return False

    def _set_lumination_to_config(self):
        level = max(0, min(10, int(self.system_config.backlight)))
        raw = max(self.BACKLIGHT_FLOOR, self.BACKLIGHT_TABLE[level])
        try:
            with open("/sys/class/backlight/backlight/brightness", "w") as f:
                f.write(str(raw))
            with open("/sys/class/backlight/backlight/bl_power", "w") as f:
                f.write("0")
        except OSError as e:
            PyUiLogger.get_logger().error(f"Miniloong: backlight write failed: {e}")

    def _set_brightness_to_config(self):
        self.panel_calibration.apply("brightness")

    def _set_contrast_to_config(self):
        self.panel_calibration.apply("contrast")

    def _set_saturation_to_config(self):
        self.panel_calibration.apply("saturation")

    def _set_hue_to_config(self):
        self.panel_calibration.apply("hue")

    def supports_brightness_calibration(self):
        return self.panel_calibration.supports("brightness")

    def supports_contrast_calibration(self):
        return self.panel_calibration.supports("contrast")

    def supports_saturation_calibration(self):
        return self.panel_calibration.supports("saturation")

    def supports_hue_calibration(self):
        return self.panel_calibration.supports("hue")

    def startup_init(self, include_wifi=True):
        self.panel_calibration.apply_all()

    # ---- audio ----

    def get_volume(self):
        return self.system_config.get_volume()

    # change_volume passes 0-100, which maps straight to the softvol Master.
    def _set_volume(self, volume):
        pct = max(0, min(100, int(volume)))
        try:
            subprocess.run(["amixer", "-M", "-q", "sset", "Master", f"{pct}%"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Miniloong: _set_volume failed: {e}")
        return volume

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
            if ControllerInput.POWER_BUTTON == controller_input:
                if length_in_seconds < 1:
                    self.sleep()
                else:
                    self.prompt_power_down()
            elif ControllerInput.VOLUME_UP == controller_input:
                self.change_volume(5)
            elif ControllerInput.VOLUME_DOWN == controller_input:
                self.change_volume(-5)

    # ---- power / battery ----

    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        try:
            with open("/sys/class/power_supply/battery/capacity") as f:
                return int(f.read().strip())
        except (OSError, ValueError):
            return 0

    @throttle.limit_refresh(5)
    def get_charge_status(self):
        for node in ("/sys/class/power_supply/usb/online", "/sys/class/power_supply/ac/online"):
            try:
                with open(node) as f:
                    if int(f.read().strip()):
                        return ChargeStatus.CHARGING
            except (OSError, ValueError):
                continue
        return ChargeStatus.DISCONNECTED

    def sleep(self):
        pass

    def get_fw_version(self):
        return darkmoss_fw_version() or "Unknown"

    def power_off_cmd(self):
        return "systemctl poweroff"

    def reboot_cmd(self):
        return "systemctl reboot"

    def prompt_power_down(self):
        DeviceCommon.prompt_power_down(self)

    # ---- wifi ----

    def supports_wifi(self):
        return True

    def is_wifi_enabled(self):
        return self.system_config.is_wifi_enabled()

    # ---- bluetooth: not wired ----

    def is_bluetooth_enabled(self):
        return False

    def disable_bluetooth(self):
        pass

    def enable_bluetooth(self):
        pass

    def get_bluetooth_scanner(self):
        return None

    # ---- launching / paths ----

    def run_cmd(self, args, dir=None, is_power_cmd=False):
        PyUiLogger.get_logger().debug(f"About to launch {args} from dir {dir}")
        subprocess.run(args, cwd=dir)

    def run_app(self, folder, launch):
        return MiyooTrimCommon.run_app(self, folder, launch)

    def run_game(self, rom_info: RomInfo) -> subprocess.Popen:
        return MiyooTrimCommon.run_game(self, rom_info)

    def get_app_finder(self):
        return MiyooAppFinder()

    def parse_favorites(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_favorites()

    def parse_recents(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_recents()

    def perform_startup_tasks(self):
        pass

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

    def take_snapshot(self, path):
        return None

    def get_save_state_image(self, rom_info: RomInfo):
        return self.get_game_system_utils().get_save_state_image(rom_info)

    def get_game_system_utils(self):
        return self.game_utils

    def get_extra_settings_options(self):
        return []

    def keep_running_on_error(self):
        return False

    def perform_sdcard_ro_check(self):
        PyUiLogger.get_logger().info("Miniloong: not checking read-only SD card status.")
