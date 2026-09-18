import os
import subprocess
import threading
from pathlib import Path

from audio.audio_player_delegate_sdl2 import AudioPlayerDelegateSdl2
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller import KeyWatcherController
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.magicx.magicx_key_mapping_provider import MagicXKeyMappingProvider
from devices.std_in_based_send_event_binary_helper import StdInBasedSendEventBinaryHelper
from devices.trimui.trim_ui_device import TrimUIDevice
from devices.utils.file_watcher import FileWatcher
from utils import throttle
from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger


class MagicXA133PDevice(TrimUIDevice):
    """MagicX A133P family (Mini Zero 28, Zero 40, XU20 V32).

    The same Allwinner A133P as the TrimUI Smart Pro, running on our own Tina
    base image (CFW/Spruce/devices in the wrapper): the same /dev/disp
    backlight, AXP2202 battery and XR829 radio the TrimUI classes drive, but no
    TrimUI daemons. Input is the kernel's simplepad gamepad, which reports the
    TrimUI evdev codes, so the TrimUI key mapping provider is reused. The shell
    resolves the input nodes at boot and exports them (EVENT_PATH_*); the
    literals here are only fallbacks.

    All three boards run our own Tina kernel: the Zero 28 on the plain SDK chain,
    the Zero 40 and the XU20 behind their stock boot0 and U-Boot. The sysfs paths
    below (battery, backlight) were confirmed on all three on 2026-09-17.
    """

    def __init__(self, device_name, main_ui_mode, system_json_path):
        self.device_name = device_name
        self.audio_player = AudioPlayerDelegateSdl2()
        self.pad_event_path = os.environ.get("EVENT_PATH_READ_INPUTS_SPRUCE") or "/dev/input/event3"
        # event0 on all three boards, measured 2026-09-17: the AXP power key enumerates
        # first. The sibling TrimUI family has a matrix keyboard there and shifts down one.
        self.power_event_path = os.environ.get("EVENT_PATH_POWER") or "/dev/input/event0"
        self.volume_event_path = os.environ.get("EVENT_PATH_VOLUME") or self.pad_event_path
        self.touch_event_path = os.environ.get("EVENT_PATH_TOUCH") or ""

        script_dir = Path(__file__).resolve().parent
        self._load_system_config(system_json_path, script_dir / 'magicx-system.json')
        if main_ui_mode:
            self.miyoo_games_file_parser = MiyooGamesFileParser()
            threading.Thread(target=self.startup_init, daemon=True).start()
            self.config_watcher_thread, self.config_watcher_thread_stop_event = FileWatcher().start_file_watcher(
                system_json_path, self.on_system_config_changed, interval=0.2,
                repeat_trigger_for_mtime_granularity_issues=True)
            # The watchers always run, as on the TrimUI siblings; enableButtonWatchers
            # is honoured where the keys are processed (TrimUIDevice.special_input).
            from controller.controller import Controller
            # Volume keys ride the gamepad node on this family (KEY_VOLUMEUP/DOWN);
            # a second evdev reader on the same node gets its own copy of the stream.
            self.volume_key_watcher = KeyWatcher(self.volume_event_path)
            Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
            threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True).start()
            self.power_key_watcher = KeyWatcher(self.power_event_path)
            threading.Thread(target=self.power_key_watcher.poll_keyboard, daemon=True).start()
            if self.supports_touch():
                self._start_touch_watcher()
        super().__init__()

    def _start_touch_watcher(self):
        if not self.touch_event_path or not os.path.exists(self.touch_event_path):
            PyUiLogger.get_logger().warning(f"Touch enabled but no touchscreen node ({self.touch_event_path!r}); touch off")
            return
        from controller.touch_watcher import TouchWatcher
        self.touch_watcher = TouchWatcher(self.touch_event_path, self)
        threading.Thread(target=self.touch_watcher.poll, daemon=True).start()

    def startup_init(self, include_wifi=True):
        self._set_lumination_to_config()
        self._set_contrast_to_config()
        self._set_saturation_to_config()
        self._set_brightness_to_config()
        self._set_hue_to_config()

    # ----- identity -----
    def get_device_name(self):
        return self.device_name

    def get_device_names(self):
        # The family token lets one Emu/App config entry cover every board in the
        # family; it mirrors device_names() in spruce/scripts/helperFunctions.sh.
        return [self.device_name, "MAGICX_A133P"]

    def get_fw_version(self):
        # The base image records the Tina config it was built from next to the marker.
        # A failed read must not name a different board, so report the launch platform.
        try:
            with open("/usr/magicx/device") as f:
                model = f.read().strip() or "unknown"
        except OSError:
            model = os.environ.get("PLATFORM", "").strip() or "unknown"
        return f"magicx-tina ({model})"

    # ----- display -----
    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        return False

    def should_scale_screen(self):
        return False

    def output_screen_width(self):
        return self.screen_width()

    def output_screen_height(self):
        return self.screen_height()

    def get_scale_factor(self):
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

    # ----- input -----
    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        # Mirrors device_get_battery_percent in magicx_a133p.sh: a 0-1 % gauge
        # reading with a healthy voltage is replaced by a voltage estimate.
        try:
            with open("/sys/class/power_supply/axp2202-battery/capacity", "r") as f:
                cap = int(f.read().strip())
        except Exception:
            return 0
        if cap <= 1:
            try:
                with open("/sys/class/power_supply/axp2202-battery/voltage_now", "r") as f:
                    v = int(f.read().strip())
                mv = v // 1000 if v > 100000 else v
                if mv >= 3500:
                    return max(2, min(100, (mv - 3400) * 100 // (4150 - 3400)))
            except Exception:
                pass
        return cap

    def get_controller_interface(self):
        return KeyWatcherController(event_path=self.pad_event_path,
                                    mapping_provider=MagicXKeyMappingProvider(),
                                    event_format='llHHi')

    def supports_touch(self):
        return False

    def supports_analog_calibration(self):
        # trimui_inputd is what the TrimUI calibrator restarts; nothing to
        # calibrate through here on the kernel gamepad.
        return False

    # ----- misc -----
    def set_theme(self, theme_path: str):
        # No stock launcher shares the theme setting on this base.
        pass

    def get_audio_system(self):
        return self.audio_player

    def get_core_name_overrides(self, core_name):
        return [core_name, core_name + "-64"]

    def might_require_surface_format_conversion(self):
        return True

    def enable_bluetooth(self):
        if not self.is_bluetooth_enabled():
            subprocess.Popen(['./bluetoothd', "-f", "/etc/bluetooth/main.conf"],
                             cwd='/usr/bin', stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.system_config.set_bluetooth(1)

    def volume_up(self):
        StdInBasedSendEventBinaryHelper.send_key_down_and_up(self.volume_event_path, 115)

    def volume_down(self):
        StdInBasedSendEventBinaryHelper.send_key_down_and_up(self.volume_event_path, 114)
