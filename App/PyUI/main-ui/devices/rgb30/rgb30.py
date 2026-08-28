import fcntl
import json
import os
import subprocess
import threading
from pathlib import Path
import sys

from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller import DictKeyMappingProvider, KeyWatcherController
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.charge.charge_status import ChargeStatus
from devices.device_common import DeviceCommon
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.process_runner import ProcessRunner
from devices.wifi.nmcli_wifi_scanner import NmcliWifiScanner
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from display.display import Display
from games.utils.device_specific.miyoo_trim_game_system_utils import MiyooTrimGameSystemUtils
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from menus.settings.button_remapper import ButtonRemapper
from utils import throttle
from utils.logger import PyUiLogger


class Rgb30(DeviceCommon):
    """Powkiddy RGB30 running dArkMoss.

    dArkMoss is our fork of dArkOS - Debian trixie - on TF1; spruce runs from
    TF2. The panel is 720x720, the same 1:1 geometry as the RG CubeXX, so the
    square themes and layouts apply unchanged. This is the only device on this
    OS, so it is a single self-contained class rather than a shared base.
    """

    # The pad's stable by-path node - singleadc-joypad, with no distro prefix,
    # confirmed on hardware.
    JOYPAD_NODE = "/dev/input/by-path/platform-singleadc-joypad-event-joystick"

    KEY_VOLUMEDOWN = 114
    KEY_VOLUMEUP = 115
    EVIOCGRAB = 0x40044590

    def __init__(self, device_name):
        self.device_name = device_name
        self.load_rgb30_system_json()
        self.button_remapper = ButtonRemapper(self.system_config)
        self.game_utils = MiyooTrimGameSystemUtils()
        DeviceCommon.__init__(self)
        self._start_volume_watcher()

    def wants_gles_context(self):
        # The Mali G52 blob on this device offers no desktop GL config at all.
        # Every RGB configuration it advertises reports EGL_RENDERABLE_TYPE
        # 0x45 - GLES 1, 2 and 3 - and none carries EGL_OPENGL_BIT, so SDL's
        # default request matched nothing and PyUI could never open a window.
        # Measured on hardware; see spruce/scripts/platform/rgb30_gbm_probe.py.
        return True

    # ---- RGB30-specific ----

    def _resolve_volume_node(self):
        # The volume rocker is on gpio-keys, a separate evdev node from the
        # joypad. It is NOT adc-keys, which declares a phantom volume capability
        # that never fires. Match by device name so a node-number shuffle does
        # not matter.
        try:
            with open("/proc/bus/input/devices") as f:
                blocks = f.read().split("\n\n")
            for blk in blocks:
                if 'Name="gpio-keys"' in blk:
                    for tok in blk.split():
                        if tok.startswith("event"):
                            return "/dev/input/" + tok
        except OSError:
            pass
        return "/dev/input/event2"

    def _start_volume_watcher(self):
        # PyUI reads the volume node itself so the menu shows the volume widget
        # and the 0-20 number updates - the main controller only watches the
        # joypad. Same mechanism the Miyoo Flip uses (a KeyWatcher plus a poll
        # thread), and map_key turns 114/115 into VOLUME_DOWN/UP -> special_input
        # -> change_volume -> Display.volume_changed.
        #
        # Grab the node exclusively (EVIOCGRAB) so while PyUI runs it owns the
        # volume keys and the shell buttons_watchdog does not double-count them.
        # When a game launches PyUI exits, the grab is released, and the shell
        # handles volume in-game.
        node = self._resolve_volume_node()
        try:
            self.volume_key_watcher = KeyWatcher(node)
            if getattr(self.volume_key_watcher, "fd", None) is not None:
                try:
                    fcntl.ioctl(self.volume_key_watcher.fd, self.EVIOCGRAB, 1)
                except OSError as e:
                    PyUiLogger.get_logger().warning(f"RGB30: could not grab {node}: {e}")
                from controller.controller import Controller
                Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
                t = threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True)
                t.start()
                PyUiLogger.get_logger().info(f"RGB30: volume watcher on {node}")
        except Exception as e:
            PyUiLogger.get_logger().error(f"RGB30: volume watcher failed: {e}")

    def map_key(self, key_code):
        if key_code == self.KEY_VOLUMEUP:
            return ControllerInput.VOLUME_UP
        elif key_code == self.KEY_VOLUMEDOWN:
            return ControllerInput.VOLUME_DOWN
        return None

    def _set_volume(self, volume):
        # The generic volume path only changes the config number; nothing sets
        # the mixer, so the menu widget moved but the audio did not - and a game
        # then played at whatever Master happened to be. Drive the
        # Master control here. change_volume passes 0-100 (config vol*5), which
        # maps straight to a Master percentage; -M applies it on the mixer's
        # perceived-loudness scale (Master is 0-65536 raw).
        pct = max(0, min(100, int(volume)))
        try:
            subprocess.run(["amixer", "-M", "-q", "sset", "Master", f"{pct}%"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            PyUiLogger.get_logger().error(f"RGB30: _set_volume failed: {e}")
        return volume

    def load_rgb30_system_json(self):
        base_dir = os.path.abspath(sys.path[0])
        self.script_dir = os.path.join(base_dir, "devices", "rgb30")
        self.parent_dir = os.path.dirname(base_dir)
        source = os.path.join(self.script_dir, "rgb30-system.json")
        system_json_path = "/mnt/SDCARD/App/PyUI/config/rgb30-system.json"
        self._load_system_config(system_json_path, Path(source))

    def _resolve_joypad(self):
        if os.path.exists(self.JOYPAD_NODE):
            PyUiLogger.get_logger().info(f"RGB30: joypad at {self.JOYPAD_NODE}")
        else:
            PyUiLogger.get_logger().error(
                "RGB30: no singleadc joypad node found, controls will not respond"
            )
        return self.JOYPAD_NODE

    def get_controller_interface(self):
        # Derived from MinUI's rgb30 port. MinUI reads the pad as SDL joystick
        # indices, and SDL2 assigns those in ascending evdev-code order, so its
        # JOY_* table walks back to the codes below. Confirmed at two points:
        # keymon.c reads evdev 317 and 318 directly and notes they surface as
        # SDL 11 and 12, which is where this ordering puts them.
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

        # 317/318 are BTN_THUMBL/BTN_THUMBR and the device does have two sticks
        # (a live UnofficialOS card reports ANALOG_STICKS=2), but there is no
        # dedicated menu button, so MinUI uses the stick clicks as its two Menu
        # buttons and so do we. A deliberate trade of L3/R3 for a menu button.
        bind(317, ControllerInput.MENU)       # BTN_THUMBL, MinUI CODE_MENU
        bind(318, ControllerInput.MENU)       # BTN_THUMBR, MinUI CODE_MENU_ALT

        bind(544, ControllerInput.DPAD_UP)
        bind(545, ControllerInput.DPAD_DOWN)
        bind(546, ControllerInput.DPAD_LEFT)
        bind(547, ControllerInput.DPAD_RIGHT)

        return KeyWatcherController(
            event_path=self._resolve_joypad(),
            mapping_provider=DictKeyMappingProvider(key_mappings),
        )

    def run_game(self, rom_info: RomInfo) -> subprocess.Popen:
        # The same path the Flip, A30 and TrimUI take: stage the command, drop
        # PyUI, and let principal.sh run it.
        #
        # This used to launch ra64.universal directly, which skipped everything
        # the shell does around a game - per-game governor, save and state
        # handling, the in-game menu, m3u generation, rumble setup. That
        # override existed because the class inherited RocknixDevice.run_game
        # back on MossySpruce, and that names a binary (ra64.rgds) this device
        # does not ship, so every launch exec'd a missing file. The base is
        # DeviceCommon now, and principal.sh has been running here the whole
        # time - runtime.sh execs it - so the standard handoff was always
        # available and there is no reason to hand-roll a launch.
        return MiyooTrimCommon.run_game(self, rom_info)

    def supports_wifi(self):
        return True

    def is_wifi_enabled(self):
        try:
            result = ProcessRunner.run(["nmcli", "radio", "wifi"], timeout=5)
            return "enabled" in (result.stdout or "").strip().lower()
        except Exception as e:
            PyUiLogger.get_logger().error(f"nmcli is_wifi_enabled failed: {e}")
        return False

    def enable_wifi(self):
        ProcessRunner.run(["nmcli", "radio", "wifi", "on"], timeout=10)

    def disable_wifi(self):
        ProcessRunner.run(["nmcli", "radio", "wifi", "off"], timeout=10)

    def get_new_wifi_scanner(self):
        return NmcliWifiScanner()

    def wifi_connect(self, ssid, password):
        # NetworkManager stores the profile and reconnects on its own from
        # then on, so this only has to run once per network.
        try:
            if password:
                cmd = ["nmcli", "device", "wifi", "connect", ssid,
                       "password", password]
            else:
                cmd = ["nmcli", "device", "wifi", "connect", ssid]

            result = ProcessRunner.run(cmd, timeout=45)

            if result and result.returncode == 0:
                PyUiLogger.get_logger().info(f"nmcli connected to {ssid}")
                return

            # Deliberately not logging nmcli's own stderr: it echoes back the
            # arguments it was given, password included.
            PyUiLogger.get_logger().error(
                f"nmcli could not connect to {ssid} "
                f"(exit {result.returncode if result else 'none'})"
            )
        except Exception as e:
            PyUiLogger.get_logger().error(f"nmcli wifi_connect failed: {e}")

    def get_wpa_supplicant_conf_path(self):
        # Not used - wifi_connect is overridden - but the WiFi menu still reads
        # it, so return a harmless path rather than None.
        return "/tmp/wpa_supplicant.conf"

    def get_device_name(self):
        return self.device_name

    def screen_width(self):
        return 720

    def screen_height(self):
        return 720

    def screen_rotation(self):
        return 0

    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        try:
            with open("/sys/class/power_supply/battery/capacity", "r") as f:
                return int(f.read().strip())
        except (OSError, ValueError):
            return 0

    @throttle.limit_refresh(5)
    def get_charge_status(self):
        # MinUI reads the charger rather than the battery's own status node.
        try:
            with open("/sys/class/power_supply/ac/online", "r") as f:
                online = int(f.read().strip())
        except (OSError, ValueError):
            return ChargeStatus.DISCONNECTED

        return ChargeStatus.CHARGING if online else ChargeStatus.DISCONNECTED

    def is_hdmi_connected(self):
        try:
            with open("/sys/class/extcon/hdmi/cable.0/state", "r") as f:
                return f.read().strip() == "1"
        except OSError:
            return False

    # ---- host behaviour ----

    def sleep(self):
        pass

    def ensure_wpa_supplicant_conf(self):
        pass

    def should_scale_screen(self):
        return self.is_hdmi_connected()

    def power_off_cmd(self):
        # Through systemd, so TF2 is unmounted cleanly. A bare poweroff leaves
        # the FAT dirty.
        return "systemctl poweroff"

    def reboot_cmd(self):
        return "systemctl reboot"

    # Why does this break? Using the script should be better than just
    # Running the direct command
    #def power_off(self):
    #    ProcessRunner.run(["/opt/muos/script/system/halt.sh", "poweroff"])
    #def reboot(self):
    #    ProcessRunner.run(["/opt/muos/script/system/halt.sh", "reboot"])

    def _set_brightness_to_config(self):
        pass

    def _set_lumination_to_config(self):
        pass

    def _set_contrast_to_config(self):
        pass

    def _set_saturation_to_config(self): 
        pass

    def _set_hue_to_config(self):
        pass

    def get_volume(self):
        return self.system_config.get_volume()

    def run_cmd(self, args, dir = None, is_power_cmd = False):
        PyUiLogger.get_logger().debug(f"About to launch app {args} from dir {dir}")
        subprocess.run(args, cwd = dir)

    def run_app(self, folder,launch):
        directory = os.path.dirname(launch)
        PyUiLogger.get_logger().debug(f"About to launch app {launch} from dir {directory}")
        subprocess.run([launch], cwd = directory)

    def map_digital_input(self, sdl_input):
        return None

    def map_analog_input(self, sdl_axis, sdl_value):
        return None

    def prompt_power_down(self):
        DeviceCommon.prompt_power_down(self)

    def change_volume(self, amount):
        from display.display import Display
        self.system_config.reload_config()
        volume = self.get_volume() + amount
        if(volume < 0):
            volume = 0
        elif(volume > 100):
            volume = 100
        self._set_volume(volume)
        self.system_config.set_volume(volume)
        self.system_config.save_config()
        Display.volume_changed(self.get_volume())

    def volume_up(self):
        self.change_volume(+5)

    def volume_down(self):
        self.change_volume(-5)

    def special_input(self, controller_input, length_in_seconds):
        if(ControllerInput.POWER_BUTTON == controller_input):
            if(length_in_seconds < 1):
                self.sleep()
            else:
                self.prompt_power_down()
        elif(ControllerInput.VOLUME_UP == controller_input):
            self.change_volume(5)
        elif(ControllerInput.VOLUME_DOWN == controller_input):
            self.change_volume(-5)

    def get_wifi_connection_quality_info(self) -> WiFiConnectionQualityInfo:
        # spruce classifies on RSSI in dBm; nmcli reports link quality 0-100,
        # so map it the usual way - 100 at -50 dBm, 0 at -100.
        try:
            result = ProcessRunner.run(
                ["nmcli", "-t", "-f", "ACTIVE,SIGNAL", "device", "wifi"],
                timeout=5,
            )

            for line in (result.stdout or "").splitlines():
                parts = line.split(":")

                if len(parts) >= 2 and parts[0] == "yes":
                    quality = max(0, min(100, int(parts[1])))
                    return WiFiConnectionQualityInfo(
                        noise_level=0,
                        signal_level=(quality // 2) - 100,
                        link_quality=quality,
                    )
        except Exception as e:
            PyUiLogger.get_logger().error(
                f"nmcli get_wifi_connection_quality_info failed: {e}"
            )

        # -200 is what device_common reads as "no signal".
        return WiFiConnectionQualityInfo(
            noise_level=0, signal_level=-200, link_quality=0
        )

    def set_wifi_power(self, value):
        pass

    def stop_wifi_services(self):
        pass

    def start_wpa_supplicant(self):
        pass

    def get_app_finder(self):
        return MiyooAppFinder()

    def parse_favorites(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_favorites()

    def parse_recents(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_recents()

    def is_bluetooth_enabled(self):
        return False #Let it be handled in muOS proper, too lazy to implement

    def disable_bluetooth(self):
        pass

    def enable_bluetooth(self):
        pass

    def perform_startup_tasks(self):
        pass

    def get_bluetooth_scanner(self):
        return None

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
        return "/mnt/union/ROMS/"

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
        option_list = []
        return option_list

    def take_snapshot(self, path):
        return None

    def get_save_state_image(self, rom_info: RomInfo):
        #TODO, where does it store this?
        return None

    def supports_brightness_calibration(self):
        return False

    def supports_contrast_calibration(self):
        return False

    def supports_saturation_calibration(self):
        return False

    def supports_hue_calibration(self):
        return False

    def keep_running_on_error(self):
        return False

    def perform_sdcard_ro_check(self):
        PyUiLogger.get_logger().info("RGB30: not checking read-only SD card status.")
