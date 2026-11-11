

import fcntl
import os
import struct

from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from devices.charge.charge_status import ChargeStatus
from devices.env.env_var_device import EnvVarDevice
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.std_in_based_send_event_binary_helper import StdInBasedSendEventBinaryHelper
from games.utils.device_specific.miyoo_trim_game_system_utils import MiyooTrimGameSystemUtils
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from utils import throttle
from utils.py_ui_config import PyUiConfig


class SpruceDevice(EnvVarDevice):
    def __init__(self, main_ui_mode):
        super().__init__(main_ui_mode)

        # Spruce uses the miyoo file format for its configs regardless of which device it is on
        self.games_file_parser = MiyooGamesFileParser()   
        self.game_utils = MiyooTrimGameSystemUtils()
        if os.environ.get("ANBERNIC_XX_BACKLIGHT_IOCTL") == "true":
            self._set_lumination_to_config()

    def _set_lumination_to_config(self):
        if os.environ.get("ANBERNIC_XX_BACKLIGHT_IOCTL") != "true":
            return super()._set_lumination_to_config()

        value = max(5, self.map_backlight_from_10_to_full_255(self.system_config.backlight) // 2)
        fd = os.open("/dev/disp", os.O_RDWR)
        try:
            fcntl.ioctl(fd, 0x102, struct.pack("QQQQ", 0, value, 0, 0))
        finally:
            os.close(fd)

    def volume_up(self):
        event_path = os.environ.get("ANBERNIC_XX_VOLUME_EVENT_PATH")
        if event_path:
            StdInBasedSendEventBinaryHelper.send_key_down_and_up(event_path, 115)
        else:
            super().volume_up()

    def volume_down(self):
        event_path = os.environ.get("ANBERNIC_XX_VOLUME_EVENT_PATH")
        if event_path:
            StdInBasedSendEventBinaryHelper.send_key_down_and_up(event_path, 114)
        else:
            super().volume_down()

    def special_input(self, controller_input, length_in_seconds):
        if os.environ.get("ANBERNIC_XX_DEVICE") != "true" or not PyUiConfig.enable_button_watchers():
            return
        if controller_input == ControllerInput.POWER_BUTTON:
            if length_in_seconds < 1:
                self.sleep()
            else:
                self.prompt_power_down()

    @throttle.limit_refresh(5)
    def get_charge_status(self):
        if os.environ.get("ANBERNIC_XX_DEVICE") != "true":
            return super().get_charge_status()
        try:
            status = self._read_status("CHARGE_STATUS_PATH", "CHARGE_STATUS_CMD")
        except Exception as e:
            self._log_status_error("the charge status", e)
            return ChargeStatus.DISCONNECTED
        if status and status.lower() == "charging":
            return ChargeStatus.CHARGING
        return ChargeStatus.DISCONNECTED

    def calibrate_sticks(self):
        # TODO get from env var which version of calibration to use and then call it
        # Can we actually make a generic UI that does something like
        # 1) from env var call a clear calibration function
        # 2) Call a env var pointing to a cmd to say calibrate left stick -> ask user to rotate left in foreground
        # 3) Call a env var pointing to a cmd to say calibrate right stick -> ask user to rotate right in foreground
        pass

    def supports_analog_calibration(self):
        # TODO base on same thing as above
        return False
    
    # Same key resolution as get_selected_emulator, which the launcher mirrors, plus the per-game override
    def get_core_for_game(self, game_system_config, rom_file_path):
        menu_options = game_system_config.get_menu_options()
        arch_key = self.get_emulator_arch(menu_options, rom_file_path)
        for key, option in menu_options.items():
            if key.startswith("Emulator") and (arch_key is None or key == arch_key) and any(name in (option.get("devices") or []) for name in self.get_device_names()):
                return game_system_config.get_effective_menu_selection(key, rom_file_path)
        return game_system_config.get_effective_menu_selection("Emulator", rom_file_path)

    # Same suffixed state folder names the TrimUI and Miyoo classes check; a missing one is just a failed exists()
    def get_core_name_overrides(self, core_name):
        return [core_name, core_name + "-64", core_name + "-32"]

    # SPRUCE uses the miyoo format for all of its emu config files
    def get_app_finder(self):
        return MiyooAppFinder()
    
    
    def parse_favorites(self) -> list[GameEntry]:
        return self.games_file_parser.parse_favorites()
    
    def parse_recents(self) -> list[GameEntry]:
        return self.games_file_parser.parse_recents()

    def run_game(self, rom_info: RomInfo):
        MiyooTrimCommon.run_game(self, rom_info)

    def run_cmd(self, args, dir = None, is_power_cmd = False):
        MiyooTrimCommon.run_cmd(self, args, dir, is_power_cmd)
            
    def run_app(self, folder,launch):
        MiyooTrimCommon.run_app(self, folder,launch)

    def get_image_for_activity(self, activity):
        return MiyooTrimCommon.get_image_for_activity(activity)
