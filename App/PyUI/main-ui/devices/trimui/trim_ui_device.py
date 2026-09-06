import ctypes
import fcntl
import math
from pathlib import Path
import re
import subprocess
import time
from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from devices.bluetooth.bluetooth_scanner import BluetoothScanner
from devices.charge.charge_status import ChargeStatus
import os
from devices.device_common import DeviceCommon
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from display.display import Display
from menus.language.language import Language
from games.utils.device_specific.miyoo_trim_game_system_utils import MiyooTrimGameSystemUtils
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from menus.settings.button_remapper import ButtonRemapper
from utils import throttle
from utils.logger import PyUiLogger

class TrimUIDevice(DeviceCommon):
    
    def __init__(self):
        self.button_remapper = ButtonRemapper(self.system_config)
        self.game_utils = MiyooTrimGameSystemUtils()
        super().__init__()

    def on_system_config_changed(self):
        old_volume = self.system_config.get_volume()
        old_wifi_enabled = self.system_config.is_wifi_enabled()
        self.system_config.reload_config()
        new_volume = self.system_config.get_volume()
        if(old_volume != new_volume):
            Display.volume_changed(new_volume)

        # Something outside this process - the physical switch's
        # scene-wifi.sh, today - can flip .wifi in this same file while PyUI
        # is already running. reload_config() above already picks up the
        # fresh value, so monitor_wifi()'s self-heal loop won't fight the
        # switch by turning WiFi back on - but the WiFi status caches still
        # need an explicit nudge so the WiFi menu/top bar icon catch up
        # immediately instead of waiting on their own throttle window.
        if(old_wifi_enabled != self.system_config.is_wifi_enabled()):
            self.get_wifi_status.force_refresh()
            self.get_ip_addr_text.force_refresh()

    def ensure_wpa_supplicant_conf(self):
        MiyooTrimCommon.ensure_wpa_supplicant_conf(self.get_wpa_supplicant_conf_path())
        
    def clear_framebuffer(self):
        pass

    def capture_framebuffer(self):
        pass

    def restore_framebuffer(self):
        pass
    

    def power_off_cmd(self):
        return "poweroff"
    

    def reboot_cmd(self):
        return "reboot"
        
    # Shared by the Brick, Brick Pro, Smart Pro and Smart Pro S. The consent
    # question (SPR-MED-199) needs the UI, so it is asked first; the
    # "Powering off" / "Rebooting" message ends the UI, and the trailing sleep
    # keeps PyUI from drawing over it while the shutdown runs.
    def _signal_osd_quit(self):
        os.makedirs("/tmp/trimui_osd", exist_ok=True)
        open("/tmp/trimui_osd/osdd_quit", "a").close()

    def _wpa_supplicant_quit(self):
        ProcessRunner.run(["killall", "wpa_supplicant"])

    def _prepare_for_power_action(self):
        self._signal_osd_quit()
        self._wpa_supplicant_quit()
        time.sleep(1)

    def power_off(self):
        repair_sd = self.sd_card_repair_consent_for("poweroff")
        if not repair_sd:
            Display.display_message(Language.label("poweringOff", "Powering off..."))
        self._prepare_for_power_action()
        time.sleep(1)
        super().power_off(repair_sd=repair_sd)
        # So we dont update the display while shutting down
        time.sleep(10)

    def reboot(self):
        repair_sd = self.sd_card_repair_consent_for("reboot")
        if not repair_sd:
            Display.display_message(Language.label("rebooting", "Rebooting..."))
        self._prepare_for_power_action()
        time.sleep(1)
        super().reboot(repair_sd=repair_sd)
        # So we dont update the display while rebooting
        time.sleep(10)

    def _set_lumination_to_config(self):
        val = self.map_backlight_from_10_to_full_255(self.system_config.backlight)
        try:
            DISP_LCD_SET_BRIGHTNESS = 0x102 
            fd = os.open("/dev/disp", os.O_RDWR)
            if fd > 0:
                # Create a ctypes array equivalent to: unsigned long param[4] = {0, val, 0, 0};
                param = (ctypes.c_ulong * 4)(0, val, 0, 0)
                # Perform ioctl with pointer to param
                fcntl.ioctl(fd, DISP_LCD_SET_BRIGHTNESS, param)
                os.close(fd)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error setting brightness: {e}")

    def _set_contrast_to_config(self):
        with open("/sys/devices/virtual/disp/disp/attr/enhance_contrast", "w") as f:
            f.write(str(self.system_config.contrast * 5))

    def _set_saturation_to_config(self):
        with open("/sys/devices/virtual/disp/disp/attr/enhance_saturation", "w") as f:
            f.write(str(self.system_config.saturation * 5))

    def _set_brightness_to_config(self):
        with open("/sys/devices/virtual/disp/disp/attr/enhance_bright", "w") as f:
            f.write(str(self.system_config.brightness * 5))

    def _set_hue_to_config(self):
        with open("/sys/devices/virtual/disp/disp/attr/color_temperature", "w") as f:
            f.write(str((self.system_config.hue * 5) - 50))

    def get_volume(self):
        return self.system_config.get_volume()

    def sleep(self):
        try:
            with open("/sys/power/state", "w") as f:
                f.write("mem")  
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failure attempting to sleep: {e}")


    def run_game(self, rom_info):
        return MiyooTrimCommon.run_game(self, rom_info)

    def run_cmd(self, args, dir = None, is_power_cmd = False):
        MiyooTrimCommon.run_cmd(self, args, dir, is_power_cmd)
        
    def run_app(self, folder,launch):
        MiyooTrimCommon.run_app(self, folder,launch)

    def map_digital_input(self, sdl_input):
        mapping = self.sdl_button_to_input.get(sdl_input, ControllerInput.UNKNOWN)
        if(ControllerInput.UNKNOWN == mapping):
            PyUiLogger.get_logger().error(f"Unknown input {sdl_input}")
        return mapping
    
    def map_key(self, key_code):
        if(116 == key_code):
            return ControllerInput.POWER_BUTTON
        if(115 == key_code):
            return ControllerInput.VOLUME_UP
        elif(114 == key_code):
            return ControllerInput.VOLUME_DOWN
        else:
            PyUiLogger.get_logger().debug(f"Unrecognized keycode {key_code}")
            return None

    
    def special_input(self, controller_input, length_in_seconds):
        if(ControllerInput.POWER_BUTTON == controller_input):
            if(length_in_seconds < 1):
                self.sleep()
            else:
                self.prompt_power_down()

    def map_analog_input(self, sdl_axis, sdl_value):
        PyUiLogger.get_logger().error(f"Received analog input axis = {sdl_axis}, value = {sdl_value}")

    def get_wifi_connection_quality_info(self) -> WiFiConnectionQualityInfo:
        try:
            result = subprocess.run(
                ["iw", "dev", "wlan0", "link"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            output = result.stdout.strip()

            if "Not connected." in output or result.returncode != 0:
                return WiFiConnectionQualityInfo(noise_level=0, signal_level=0, link_quality=0)

            signal_level = 0
            link_quality = 0  # This won't be available directly via iw, unless you derive it

            # Extract signal level (in dBm)
            signal_match = re.search(r"signal:\s*(-?\d+)\s*dBm", output)
            if signal_match:
                signal_level = int(signal_match.group(1))

            # Optional: derive link quality heuristically (e.g., map signal strength to 0–70 or 0–100)
            # Example rough mapping:
            if signal_level <= -100:
                link_quality = 0
            elif signal_level >= -50:
                link_quality = 70
            else:
                link_quality = int((signal_level + 100) * 1.4)  # Maps -100..-50 dBm to 0..70

            return WiFiConnectionQualityInfo(
                noise_level=0,  # Not available via `iw`
                signal_level=signal_level,
                link_quality=link_quality
            )

        except Exception as e:
            PyUiLogger.get_logger().error(f"An error occurred {e}")
            return WiFiConnectionQualityInfo(noise_level=0, signal_level=0, link_quality=0)
             
    def set_wifi_power(self, value):
        pass

    def stop_wifi_services(self):
        MiyooTrimCommon.stop_wifi_services(self)

    def start_wpa_supplicant(self):
        MiyooTrimCommon.start_wpa_supplicant(self)

    def is_wifi_enabled(self):
        return self.system_config.is_wifi_enabled()

    def disable_wifi(self):
        MiyooTrimCommon.disable_wifi(self)

    def enable_wifi(self):
        MiyooTrimCommon.enable_wifi(self)

    @throttle.limit_refresh(5)
    def get_charge_status(self):
        #Probably need to find the power and not just usb
        with open("/sys/class/power_supply/axp2202-usb/online", "r") as f:
            ac_online = int(f.read().strip())
            
        if(ac_online):
           return ChargeStatus.CHARGING
        else:
            return ChargeStatus.DISCONNECTED
    
    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        with open("/sys/class/power_supply/axp2202-battery/capacity", "r") as f:
            return int(f.read().strip()) 
        return 0
        
    def get_app_finder(self):
        return MiyooAppFinder()
    
    def parse_favorites(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_favorites()
    
    def parse_recents(self) -> list[GameEntry]:
        return self.miyoo_games_file_parser.parse_recents()

    def is_bluetooth_enabled(self):
        return self.system_config.is_bluetooth_enabled()
    
    
    def disable_bluetooth(self):
        PyUiLogger.get_logger().info(f"Disabling Bluetooth")
        ProcessRunner.run(["killall","-15","bluetoothd"])
        time.sleep(0.1)  
        ProcessRunner.run(["killall","-9","bluetoothd"])
        self.system_config.set_bluetooth(0)

    def perform_startup_tasks(self):
        pass

    def get_bluetooth_scanner(self):
        return BluetoothScanner()

    def get_favorites_path(self):
        return "/mnt/SDCARD/Saves/pyui-favorites.json"
        
    def get_recents_path(self):
        return "/mnt/SDCARD/Saves/pyui-recents.json"
            
    def get_apps_config_path(self):
        return "/mnt/SDCARD/Saves/pyui-apps.json"

    def get_collections_path(self):
        return "/mnt/SDCARD/Collections/"

    def get_state_path(self):
        return "/mnt/SDCARD/Saves/pyui-state.json"

    def launch_stock_os_menu(self):
        pass

    def calibrate_sticks(self):
        pass

    def supports_analog_calibration(self):
        return False

    def supports_image_resizing(self):
        return True

    def remap_buttons(self):
        self.button_remapper.remap_buttons()

    def supports_wifi(self):
        return True
    
    def get_game_system_utils(self):
        return self.game_utils
    
    def get_roms_dir(self):
        return "/mnt/SDCARD/Roms/"

    def take_snapshot(self, path):
        return None
    
    def supports_brightness_calibration():
        return True

    def supports_contrast_calibration():
        return True

    def supports_saturation_calibration():
        return True

    def supports_hue_calibration():
        return True

    def get_save_state_image(self, rom_info: RomInfo):
        return self.get_game_system_utils().get_save_state_image(rom_info)

    def get_fw_version(self):
        try:
            with open(f"/etc/version") as f:
                return f.read().strip()
        except Exception as e:
            PyUiLogger.get_logger().error(f"Could not read FW version : {e}")
            return "Unknown"

    def get_core_for_game(self, game_system_config, rom_file_path):
        core = game_system_config.get_effective_menu_selection("Emulator", rom_file_path)
        if(core is None):
            core = game_system_config.get_effective_menu_selection("Emulator_64", rom_file_path)
        return core
    
    # supports_timezone_setting and prompt_timezone_update come from
    # DeviceCommon now, so the zone list matches the other devices.

    def apply_timezone(self, timezone):
        """
        timezone example: "America/New_York"

        The shared behaviour sets TZ and republishes it. On top of that the
        TrimUI points /etc/localtime at the same file, so anything that reads
        the system timezone rather than the environment agrees, and writes the
        result back to the hardware clock.
        """
        if not super().apply_timezone(timezone):
            return False

        zoneinfo_path = Path(self.get_zoneinfo_dir()) / timezone
        localtime_path = Path("/etc/localtime")

        # Update system timezone symlink
        try:
            subprocess.run(
                ["ln", "-sf", str(zoneinfo_path), str(localtime_path)],
                check=True
            )
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to update /etc/localtime: {e}")

        self.sync_hw_clock()
        return True

    @throttle.limit_refresh(1)
    def post_present_operations(self):
        self.clear_display_cache_if_memory_full("MemAvailable", 100)        

    def check_for_button_remap(self, input):
        return self.button_remapper.get_mappping(input)

    def get_image_for_activity(self, activity):
        return MiyooTrimCommon.get_image_for_activity(activity)