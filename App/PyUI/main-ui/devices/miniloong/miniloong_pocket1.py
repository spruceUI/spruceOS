import fcntl
import os
import subprocess
import sys
import threading
from pathlib import Path

import sdl2

from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller import KeyWatcherController
from devices.charge.charge_status import ChargeStatus
from devices.device_common import DeviceCommon
from devices.miyoo_trim_mapping_provider import MiyooTrimKeyMappingProvider
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from menus.games.utils.rom_info import RomInfo
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from games.utils.device_specific.miyoo_trim_game_system_utils import MiyooTrimGameSystemUtils
from games.utils.game_entry import GameEntry
from menus.settings.button_remapper import ButtonRemapper
from utils import throttle
from utils.logger import PyUiLogger


class MiniloongPocket1(DeviceCommon):
    """Miniloong Pocket 1 (RK3566, Mali-G52) on the vendor buildroot firmware.

    Same silicon as the Miyoo Flip, but none of Miyoo's daemons: the pad is a
    plain kernel evdev device, power is the rk805 pwrkey node, audio is the
    rk817 codec on ALSA card 1. The panel is a fixed 720x960 portrait mode used
    in landscape, so this is the A30's rotation situation at 960x720 - PyUI
    renders a 960x720 canvas and Display rotates it by screen_rotation().

    Shape follows the RGB30 class (DeviceCommon + raw evdev), the other
    non-Miyoo RK3566 port. Hardware facts marked UNVERIFIED come from source
    reading, not a board; see ~/ai/CFW/Miniloong/TODO.md.
    """

    # Stable by-path link the stock firmware creates for the pad
    # (Jawaka input_roster_mlp1.c). UNVERIFIED on hardware.
    JOYPAD_NODE = "/dev/input/by-path/platform-loong1_joypad-event-joystick"
    INPUT_NODES_FILE = "/tmp/miniloong_input_nodes"

    KEY_VOLUMEDOWN = 114
    KEY_VOLUMEUP = 115
    KEY_POWER = 116
    EVIOCGRAB = 0x40044590

    AUDIO_CARD = "1"
    # rk817 DAC taper: ~167 barely audible, 210 the calibrated ceiling, 252
    # painful (Leaf 00-audio-init.sh). Config volume 0-100 maps onto 150..210.
    DAC_MIN = 150
    DAC_MAX = 210
    # Backlight raw <= 55 flickers on this panel (Jawaka device_mlp1.c:26).
    BACKLIGHT_FLOOR = 60

    def __init__(self, device_name, main_ui_mode=True):
        self.device_name = device_name
        os.environ.setdefault("SDL_VIDEODRIVER", "KMSDRM")
        os.environ.setdefault("SDL_RENDER_DRIVER", "kmsdrm")
        os.environ.setdefault("KMSDRM_DEVICE", "/dev/dri/card0")
        sdl2.SDL_SetHint(sdl2.SDL_HINT_RENDER_DRIVER, b"opengles2")
        sdl2.SDL_SetHint(sdl2.SDL_HINT_RENDER_OPENGL_SHADERS, b"1")
        sdl2.SDL_SetHint(sdl2.SDL_HINT_FRAMEBUFFER_ACCELERATION, b"1")
        self.load_miniloong_system_json()
        self.button_remapper = ButtonRemapper(self.system_config)
        self.game_utils = MiyooTrimGameSystemUtils()
        self.miyoo_games_file_parser = MiyooGamesFileParser()
        DeviceCommon.__init__(self)
        if main_ui_mode:
            threading.Thread(target=self.startup_init, daemon=True).start()
            self._start_key_watchers()

    def wants_gles_context(self):
        # The Mali-G52 blob offers GLES configs only (measured on the RGB30's
        # identical GPU; see rgb30_gbm_probe.py).
        return True

    # ---- config ----

    def load_miniloong_system_json(self):
        base_dir = os.path.abspath(sys.path[0])
        self.script_dir = os.path.join(base_dir, "devices", "miniloong")
        source = os.path.join(self.script_dir, "miniloong-system.json")
        self._load_system_config("/mnt/SDCARD/Saves/miniloong-system.json", Path(source))

    def startup_init(self):
        self._set_lumination_to_config()
        self._set_volume(self.get_volume())

    # ---- input ----

    def _read_input_nodes_file(self):
        nodes = {}
        try:
            with open(self.INPUT_NODES_FILE) as f:
                for line in f:
                    if "=" in line:
                        key, value = line.strip().split("=", 1)
                        nodes[key] = value.strip("'\"")
        except OSError:
            pass
        return nodes

    def _resolve_named_node(self, name_fragments):
        try:
            with open("/proc/bus/input/devices") as f:
                blocks = f.read().split("\n\n")
            for blk in blocks:
                if any(f'Name="{frag}' in blk or frag in blk.split("\n")[0] for frag in name_fragments):
                    for tok in blk.split():
                        if tok.startswith("event"):
                            return "/dev/input/" + tok
        except OSError:
            pass
        return None

    def _resolve_power_node(self):
        node = self._read_input_nodes_file().get("EVENT_PATH_POWER")
        if node and os.path.exists(node):
            return node
        return self._resolve_named_node(["rk805 pwrkey", "pwrkey"])

    def _resolve_volume_node(self):
        node = self._read_input_nodes_file().get("EVENT_PATH_VOLUME")
        power = self._resolve_power_node()
        if node and os.path.exists(node) and node != power:
            return node
        # Whether a dedicated rocker exists is UNVERIFIED; the shell side
        # points EVENT_PATH_VOLUME at the power node when it finds none.
        return None

    def _start_key_watchers(self):
        from controller.controller import Controller

        for label, node in (("power", self._resolve_power_node()), ("volume", self._resolve_volume_node())):
            if not node:
                PyUiLogger.get_logger().info(f"Miniloong: no {label} key node")
                continue
            try:
                watcher = KeyWatcher(node)
                if getattr(watcher, "fd", None) is not None and label == "volume":
                    try:
                        fcntl.ioctl(watcher.fd, self.EVIOCGRAB, 1)
                    except OSError as e:
                        PyUiLogger.get_logger().warning(f"Miniloong: could not grab {node}: {e}")
                Controller.add_button_watcher(watcher.poll_keyboard)
                threading.Thread(target=watcher.poll_keyboard, daemon=True).start()
                setattr(self, f"{label}_key_watcher", watcher)
                PyUiLogger.get_logger().info(f"Miniloong: {label} watcher on {node}")
            except Exception as e:
                PyUiLogger.get_logger().error(f"Miniloong: {label} watcher failed: {e}")

    def map_key(self, key_code):
        if key_code == self.KEY_VOLUMEUP:
            return ControllerInput.VOLUME_UP
        if key_code == self.KEY_VOLUMEDOWN:
            return ControllerInput.VOLUME_DOWN
        if key_code == self.KEY_POWER:
            return ControllerInput.POWER_BUTTON
        return None

    def _resolve_joypad(self):
        if os.path.exists(self.JOYPAD_NODE):
            PyUiLogger.get_logger().info(f"Miniloong: joypad at {self.JOYPAD_NODE}")
        else:
            PyUiLogger.get_logger().error("Miniloong: no loong1_joypad node found, controls will not respond")
        return self.JOYPAD_NODE

    def get_controller_interface(self):
        # Standard Linux gamepad codes with hat axes for the D-pad, the same
        # table the Flip and TrimUI devices use. UNVERIFIED for this pad.
        return KeyWatcherController(
            event_path=self._resolve_joypad(),
            mapping_provider=MiyooTrimKeyMappingProvider(),
            event_format="llHHi",
        )

    def map_digital_input(self, sdl_input):
        return None

    def map_analog_input(self, sdl_axis, sdl_value):
        return None

    # ---- screen ----

    def get_device_name(self):
        return self.device_name

    def screen_width(self):
        return 960

    def screen_height(self):
        return 720

    def screen_rotation(self):
        # A30 convention for a portrait panel used in landscape. Direction
        # UNVERIFIED (MLP1-003) - flip to 90 if the image comes up upside down.
        return 270

    def output_screen_width(self):
        if self.should_scale_screen():
            return 1920
        return self.screen_height()

    def output_screen_height(self):
        if self.should_scale_screen():
            return 1080
        return self.screen_width()

    def get_scale_factor(self):
        return 2 if self.is_hdmi_connected() else 1

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
        raw = self.map_backlight_from_10_to_full_255(self.system_config.backlight)
        raw = max(self.BACKLIGHT_FLOOR, int(raw))
        try:
            with open("/sys/class/backlight/backlight/brightness", "w") as f:
                f.write(str(raw))
        except OSError as e:
            PyUiLogger.get_logger().error(f"Miniloong: backlight write failed: {e}")

    def _set_brightness_to_config(self):
        pass

    def _set_contrast_to_config(self):
        pass

    def _set_saturation_to_config(self):
        pass

    def _set_hue_to_config(self):
        pass

    # ---- audio ----

    def get_volume(self):
        return self.system_config.get_volume()

    def _set_volume(self, volume):
        pct = max(0, min(100, int(volume)))
        try:
            if pct == 0:
                subprocess.run(["amixer", "-c", self.AUDIO_CARD, "-q", "sset", "Playback Path", "OFF"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            else:
                raw = self.DAC_MIN + (self.DAC_MAX - self.DAC_MIN) * pct // 100
                subprocess.run(["amixer", "-c", self.AUDIO_CARD, "-q", "cset",
                                "name='DAC Playback Volume'", f"{raw},{raw}"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.run(["amixer", "-c", self.AUDIO_CARD, "-q", "sset", "Playback Path", "SPK"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Miniloong: _set_volume failed: {e}")
        return volume

    def change_volume(self, amount):
        from display.display import Display
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
        # spruce's sleep helper owns suspend on every platform; PyUI only asks.
        ProcessRunner.run(["/mnt/SDCARD/spruce/scripts/sleep_helper.sh"], timeout=None)

    def power_off_cmd(self):
        return "poweroff"

    def reboot_cmd(self):
        return "reboot"

    def prompt_power_down(self):
        DeviceCommon.prompt_power_down(self)

    # ---- wifi: owned by the stock S40network/dhcpcd; menu not wired yet (MLP1-008) ----

    def supports_wifi(self):
        return False

    def is_wifi_enabled(self):
        try:
            with open("/sys/class/net/wlan0/operstate") as f:
                return f.read().strip() == "up"
        except OSError:
            return False

    def enable_wifi(self):
        pass

    def disable_wifi(self):
        pass

    def get_new_wifi_scanner(self):
        return None

    def wifi_connect(self, ssid, password):
        pass

    def get_wpa_supplicant_conf_path(self):
        return "/tmp/wpa_supplicant.conf"

    def ensure_wpa_supplicant_conf(self):
        pass

    def get_wifi_connection_quality_info(self) -> WiFiConnectionQualityInfo:
        return WiFiConnectionQualityInfo(noise_level=0, signal_level=-200, link_quality=0)

    def set_wifi_power(self, value):
        pass

    def stop_wifi_services(self):
        pass

    def start_wpa_supplicant(self):
        pass

    # ---- bluetooth: not wired (stock btmanager equivalent unknown) ----

    def is_bluetooth_enabled(self):
        return False

    def disable_bluetooth(self):
        pass

    def enable_bluetooth(self):
        pass

    def get_bluetooth_scanner(self):
        return None

    # ---- launching / paths: the generic spruce flow (Emu launch.sh -> principal) ----

    def run_cmd(self, args, dir=None, is_power_cmd=False):
        PyUiLogger.get_logger().debug(f"About to launch {args} from dir {dir}")
        subprocess.run(args, cwd=dir)

    def run_app(self, folder, launch):
        directory = os.path.dirname(launch)
        PyUiLogger.get_logger().debug(f"About to launch app {launch} from dir {directory}")
        subprocess.run([launch], cwd=directory)

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
        # Exit-to-stock is a boot-session decision (a flag the supervisor reads);
        # PyUI just leaves.
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

    def run_game(self, rom_info: RomInfo) -> "subprocess.Popen":
        # Launch through the standard spruce Emu flow: MiyooTrimCommon writes
        # the platform launch command and lets principal.sh run it, so the
        # per-emulator setup in spruce/scripts/emu/lib (setup_for_retroarch,
        # the retroarch-Miniloong.cfg staging, core resolution) all applies -
        # exactly as on the Flip. The same helper the Flip's run_game uses.
        return MiyooTrimCommon.run_game(self, rom_info)

    def take_snapshot(self, path):
        # Screenshots are taken by the shell (spruce/flip/screenshot.sh via
        # take_screenshot in Miniloong.sh); PyUI has no in-menu capture here.
        return None

    def get_save_state_image(self, rom_info: RomInfo):
        # Save-state thumbnails are not wired for this platform yet (MLP1-009).
        return None

    # Panel colour calibration (modetest on the Flip) is UNVERIFIED on this
    # board, so the display menu hides these knobs until a device confirms them.
    def supports_brightness_calibration(self):
        return False

    def supports_contrast_calibration(self):
        return False

    def supports_saturation_calibration(self):
        return False

    def supports_hue_calibration(self):
        return False

    def get_game_system_utils(self):
        return self.game_utils

    def get_extra_settings_options(self):
        return []
