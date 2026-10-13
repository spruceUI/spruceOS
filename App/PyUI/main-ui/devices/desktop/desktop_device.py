import os
from pathlib import Path

import sdl2
import sdl2.ext

from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from devices.charge.charge_status import ChargeStatus
from devices.desktop.desktop_capture import capture_frame
from devices.desktop.desktop_controller_interface import DesktopControllerInterface, DesktopQuit
from devices.desktop.desktop_options import DesktopOptions
from devices.desktop.desktop_script import format_script
from devices.device_common import DeviceCommon
from devices.miyoo.device_user_config import DeviceUserConfig
from games.utils.device_specific.miyoo_trim_game_system_utils import MiyooTrimGameSystemUtils
from menus.language.language import Language
from utils.config_copier import ConfigCopier
from utils.logger import PyUiLogger


class DesktopUserConfig(DeviceUserConfig):
    # The settings every device on a card shares (the timezone) live in the desktop's data
    # folder too; DesktopDevice points this at it before loading the config.
    SHARED_CONFIG_PATH = None


class DesktopDevice(DeviceCommon):
    """PyUI in a window on a Mac or PC, for working on PyUI, themes and PyUI-based apps without
    a handheld: any resolution, any theme, keyboard or gamepad, scripted input and screenshots.
    See App/PyUI/docs/desktop_readme.txt.

    Content (apps, systems, themes, ROMs) is read from a read-only SD card - by default the
    SpruceOS checkout this PyUI is in - and everything PyUI writes goes to a separate data
    folder. Nothing touches hardware or runs the CFW's scripts: display, sound and radio
    settings are saved and otherwise ignored, power off ends the run, and games and apps are
    not started.
    """

    # Fixed, so screenshots of the top bar don't change from run to run.
    BATTERY_PERCENT = 87

    def __init__(self, main_ui_mode=True, options=None):
        self.options = options or DesktopOptions.from_environ()
        self.main_ui_mode = main_ui_mode
        if self.options.headless:
            # Before Display.init: SDL picks its drivers when it starts.
            os.environ["SDL_VIDEODRIVER"] = "dummy"
            os.environ["SDL_RENDER_DRIVER"] = "software"
        self.saves_dir = self.options.data / "Saves"
        self.saves_dir.mkdir(parents=True, exist_ok=True)
        DesktopUserConfig.SHARED_CONFIG_PATH = str(self.saves_dir / "spruce" / "shared-system.json")
        config_path = self.saves_dir / "desktop-system.json"
        ConfigCopier.ensure_config(str(config_path), Path(__file__).with_name("desktop-system.json"))
        self.system_config = DesktopUserConfig(str(config_path))
        if self.options.theme:
            # Kept like a theme picked in the menu, so the next run starts with it too.
            self.system_config.set_theme(self.options.theme)
        self.game_utils = MiyooTrimGameSystemUtils(
            roms_path=os.path.join(self.options.roms, ""),
            emu_path=os.path.join(self.options.sdcard, "Emu", ""))
        self.controller_interface = None
        DeviceCommon.__init__(self)
        PyUiLogger.get_logger().info(
            f"Desktop {self.options.width}x{self.options.height}: SD card {self.options.sdcard}, "
            f"ROMs {self.options.roms}, data {self.options.data}")

    # ---- Screen -------------------------------------------------------------

    def get_device_name(self):
        return "DESKTOP"

    def screen_width(self):
        return self.options.width

    def screen_height(self):
        return self.options.height

    def output_screen_width(self):
        return self.options.width

    def output_screen_height(self):
        return self.options.height

    def should_scale_screen(self):
        return False

    def create_window(self, width, height):
        # A normal window at the device's size times the zoom, not a fullscreen one the size
        # of the monitor. Display stretches its canvas over the whole window.
        scale = self.options.scale
        return sdl2.ext.Window(
            f"PyUI {self.options.width}x{self.options.height}",
            size=(self.options.width * scale, self.options.height * scale),
            flags=sdl2.SDL_WINDOW_SHOWN)

    def save_screenshot(self, name):
        """Save the frame on screen as <shots>/<name>.png (script shot: steps and F8)."""
        path = self.options.shots / f"{name}.png"
        capture_frame(path)
        PyUiLogger.get_logger().info(f"Captured {path}")

    def take_snapshot(self, path):
        capture_frame(path)
        return path

    # The panel settings are saved like on a handheld, and not applied.
    def _set_lumination_to_config(self):
        pass

    def _set_brightness_to_config(self):
        pass

    def _set_contrast_to_config(self):
        pass

    def _set_saturation_to_config(self):
        pass

    def _set_hue_to_config(self):
        pass

    def supports_brightness_calibration(self):
        return True

    def supports_contrast_calibration(self):
        return True

    def supports_saturation_calibration(self):
        return True

    def supports_hue_calibration(self):
        return True

    # ---- Input --------------------------------------------------------------

    def get_controller_interface(self):
        if self.controller_interface is None:
            on_script_progress = self._save_script_progress if self.options.script_state else None
            self.controller_interface = DesktopControllerInterface(
                self.options.script, self.save_screenshot, self.options.exit_after_script,
                on_script_progress)
        return self.controller_interface

    def _save_script_progress(self, steps):
        self.options.script_state.write_text(format_script(steps), encoding="utf-8")

    def map_digital_input(self, sdl_input):
        return None

    def map_analog_input(self, sdl_axis, sdl_value):
        return None

    def special_input(self, controller_input, length_in_seconds):
        pass

    def remap_buttons(self):
        self.button_remapper.remap_buttons()

    def calibrate_sticks(self):
        pass

    def supports_analog_calibration(self):
        return False

    # ---- Power and battery ----------------------------------------------------

    def get_battery_percent(self):
        return self.BATTERY_PERCENT

    def get_charge_status(self):
        return ChargeStatus.DISCONNECTED

    def power_off_cmd(self):
        return None

    def reboot_cmd(self):
        return None

    def power_off(self):
        raise DesktopQuit()

    def reboot(self):
        # desktop.py starts PyUI again, as spruce does after a reboot.
        self.exit_pyui()

    def sleep(self):
        pass

    def set_cpu_low_power(self):
        pass

    def set_cpu_normal(self):
        pass

    def sync_hw_clock(self):
        pass

    # ---- Sound ----------------------------------------------------------------

    def get_volume(self):
        return self.system_config.get_volume()

    def change_volume(self, amount):
        from display.display import Display
        self.system_config.reload_config()
        volume = max(0, min(100, self.get_volume() + amount))
        self.system_config.set_volume(volume)
        self.system_config.save_config()
        Display.volume_changed(self.get_volume())

    def volume_up(self):
        self.change_volume(+5)

    def volume_down(self):
        self.change_volume(-5)

    # ---- Network --------------------------------------------------------------

    def supports_wifi(self):
        return False

    def is_wifi_enabled(self):
        return False

    def get_wpa_supplicant_conf_path(self):
        return None

    def get_mac_address(self, iface="wlan0"):
        return Language.label("aboutUnknown", "Unknown")

    # ---- Content and storage ----------------------------------------------------

    def get_app_finder(self):
        return MiyooAppFinder(os.path.join(self.options.sdcard, "App", ""))

    def get_game_system_utils(self):
        return self.game_utils

    def get_roms_dir(self):
        return os.path.join(self.options.roms, "")

    def get_saves_dir(self):
        return os.path.join(self.saves_dir, "")

    def get_state_path(self):
        return str(self.saves_dir / "pyui-state.json")

    def get_favorites_path(self):
        return str(self.saves_dir / "pyui-favorites.json")

    def get_recents_path(self):
        return str(self.saves_dir / "pyui-recents.json")

    def get_apps_config_path(self):
        return str(self.saves_dir / "pyui-apps.json")

    def get_collections_path(self):
        return os.path.join(self.options.data, "Collections", "")

    def parse_favorites(self):
        # The stock Miyoo/TrimUI lists in Roms/; there is no stock OS here.
        return []

    def parse_recents(self):
        return []

    def get_save_state_image(self, rom_info):
        return self.game_utils.get_save_state_image(rom_info)

    def supports_image_resizing(self):
        # The box art resizer rewrites images next to the ROMs, which are read only here.
        return False

    def perform_sdcard_ro_check(self):
        pass

    # ---- Launching ----------------------------------------------------------------

    def run_game(self, rom_info):
        PyUiLogger.get_logger().info(f"Desktop: not launching {rom_info.rom_file_path}")
        return None

    def run_app(self, folder, launch):
        PyUiLogger.get_logger().info(f"Desktop: not launching {launch} in {folder}")

    def run_cmd(self, args, dir=None, is_power_cmd=False):
        # These are the CFW's device scripts: never run them on the host.
        PyUiLogger.get_logger().info(f"Desktop: not running {args}")

    def launch_stock_os_menu(self):
        pass

    def perform_startup_tasks(self):
        pass

    def startup_init(self, include_wifi):
        pass

    def get_extra_settings_options(self):
        return []
