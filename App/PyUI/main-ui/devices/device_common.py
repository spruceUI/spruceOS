

import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from audio.audio_player_none import AudioPlayerNone
from controller.controller_inputs import ControllerInput
from menus.language.language import Language
from devices.abstract_device import AbstractDevice
from devices.miyoo.device_user_config import DeviceUserConfig
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_scanner import WiFiScanner
from devices.wifi.wifi_status import WifiStatus
from display.display import Display
from display.font_purpose import FontPurpose
from menus.settings.button_remapper import ButtonRemapper
from menus.settings.wifi_menu import WifiMenu
from utils import throttle
from utils.config_copier import ConfigCopier
from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig


class DeviceCommon(AbstractDevice):

    def __init__(self):
        self.last_cache_clear = 0
        self.button_remapper = ButtonRemapper(self.system_config)

    def prompt_power_down(self):
        from display.display import Display
        from themes.theme import Theme
        from controller.controller import Controller
        while(True):
            PyUiLogger.get_logger().info("Prompting for shutdown")
            Display.clear("Power")
            Display.render_text_centered(Language.label("powerDownPrompt", "Would you like to power down?"),self.screen_width()//2, self.screen_height()//2,Theme.text_color(FontPurpose.LIST), purpose=FontPurpose.LIST)
            if(self.reboot_cmd() is not None):
                Display.render_text_centered(Language.label("powerDownOptionsWithReboot", "A = Power Down, X = Reboot, B = Cancel"),self.screen_width() //2, self.screen_height()//2+100,Theme.text_color(FontPurpose.LIST), purpose=FontPurpose.LIST)
            else:
                Display.render_text_centered(Language.label("powerDownOptions", "A = Power Down, B = Cancel"),self.screen_width() //2, self.screen_height()//2+100,Theme.text_color(FontPurpose.LIST), purpose=FontPurpose.LIST)
            Display.present()
            if(Controller.get_input()):
                if(Controller.last_input() == ControllerInput.A):
                    self.power_off()
                elif(Controller.last_input() == ControllerInput.X and self.reboot_cmd is not None):
                    self.reboot()
                elif(Controller.last_input() == ControllerInput.B):
                    return

    def power_off(self):
        if PyUiConfig.get_poweroff_cmd():
            self.run_cmd([PyUiConfig.get_poweroff_cmd()], is_power_cmd=True)
        else:
            self.run_cmd([self.power_off_cmd()], is_power_cmd=True)

    def reboot(self):
        if PyUiConfig.get_reboot_cmd():
            self.run_cmd([PyUiConfig.get_reboot_cmd()], is_power_cmd=True)
        else:
            self.run_cmd([self.reboot_cmd()], is_power_cmd=True)


    def input_timeout_default(self):
        return 1/12 # 12 fps
    

    def screen_rotation(self):
        return 0

    def map_backlight_from_10_to_full_255(self,lumination_level, min_level=1):
        if lumination_level == 10:
            return 255
        elif lumination_level == 9:
            return 225
        elif lumination_level == 8:
            return 200
        elif lumination_level == 7:
            return 175
        elif lumination_level == 6:
            return 150
        elif lumination_level == 5:
            return 125
        elif lumination_level == 4:
            return 100
        elif lumination_level == 3:
            return 75
        elif lumination_level == 2:
            return 50
        elif lumination_level == 1:
            return 25
        else: 
            return min_level
        
    def lower_lumination(self):
        self.system_config.reload_config()
        if(self.system_config.backlight > 0):
            self.system_config.set_backlight(self.system_config.backlight - 1)
            self.system_config.save_config()
            self._set_lumination_to_config()

    def raise_lumination(self):
        self.system_config.reload_config()
        if(self.system_config.backlight < 10):
            self.system_config.set_backlight(self.system_config.backlight + 1)
            self.system_config.save_config()
            self._set_lumination_to_config()

    def lower_contrast(self):
        self.system_config.reload_config()
        if(self.system_config.contrast > 1): # don't allow 0 contrast
            self.system_config.set_contrast(self.system_config.contrast - 1)
            self.system_config.save_config()
            self._set_contrast_to_config()

    def raise_contrast(self):
        self.system_config.reload_config()
        if(self.system_config.contrast < 20):
            self.system_config.set_contrast(self.system_config.contrast + 1)
            self.system_config.save_config()
            self._set_contrast_to_config()

    def lower_brightness(self):
        self.system_config.reload_config()
        if(self.system_config.brightness > 0): 
            self.system_config.set_brightness(self.system_config.brightness - 1)
            self.system_config.save_config()
            self._set_brightness_to_config()

    def raise_brightness(self):
        self.system_config.reload_config()
        if(self.system_config.brightness < 20):
            self.system_config.set_brightness(self.system_config.brightness + 1)
            self.system_config.save_config()
            self._set_brightness_to_config()

    def lower_saturation(self):
        self.system_config.reload_config()
        if(self.system_config.saturation > 0):
            self.system_config.set_saturation(self.system_config.saturation - 1)
            self.system_config.save_config()
            self._set_saturation_to_config()

    def raise_saturation(self):
        self.system_config.reload_config()
        if(self.system_config.saturation < 20):
            self.system_config.set_saturation(self.system_config.saturation + 1)
            self.system_config.save_config()
            self._set_saturation_to_config()

    def lower_hue(self):
        self.system_config.reload_config()
        if(self.system_config.hue > 0):
            self.system_config.set_hue(self.system_config.hue - 1)
            self.system_config.save_config()
            self._set_hue_to_config()

    def raise_hue(self):
        self.system_config.reload_config()
        if(self.system_config.hue < 20):
            self.system_config.set_hue(self.system_config.hue + 1)
            self.system_config.save_config()
            self._set_hue_to_config()


    def hue(self):
        return self.system_config.get_hue()
    

    def lumination(self):
        return self.system_config.backlight
    

    def contrast(self):
        return self.system_config.get_contrast()


    def brightness(self):
        return self.system_config.get_brightness()
    

    def saturation(self):
        return self.system_config.get_saturation()

    def get_display_volume(self):
        return self.get_volume()
            
    def is_wifi_up(self):
        result = ProcessRunner.run(["ip", "link", "show", "wlan0"], print=False)
        return "UP" in result.stdout

    def wifi_error_detected(self):
        self.wifi_error = True
        
    def connection_seems_up(self):
        try:
            result = ProcessRunner.run(
                ["ping", "-c", "1", "1.1.1.1"],
                timeout=1,
                print=False)
            
            return not ("Network is unreachable") in result.stderr

        except subprocess.TimeoutExpired:
            return False
    
    def monitor_wifi(self):
        self.wifi_error = False
        self.last_successful_ping_time = time.time()
        fail_count = 0
        restart_count = 0
        while True:
            if self.is_wifi_enabled():
                if self.wifi_error or not self.is_wifi_up():
                    self.wifi_error = False
                    fail_count = 0
                    PyUiLogger.get_logger().error("Detected wlan0 disappeared, restarting wifi services")
                    PyUiLogger.get_logger().info("Restarting WiFi services")
                    self.stop_wifi_services()
                    self.start_wifi_services(foreground_call=False)
                else:
                    if time.time() - self.last_successful_ping_time > 30:
                        if(self.connection_seems_up()):
                            self.last_successful_ping_time = time.time()
                            fail_count = 0
                            restart_count = 0
                        else:
                            PyUiLogger.get_logger().error("WiFi connection looks to be down")
                            fail_count+=1
                            if(fail_count > 3):
                                if(restart_count > 5):
                                    PyUiLogger.get_logger().error("Cannot get WiFi connection so disabling WiFi")
                                    self.disable_wifi()
                                else:
                                    PyUiLogger.get_logger().error("Going to reinitialize WiFi")
                                    restart_count += 1
                                    self.wifi_error = True


            time.sleep(10)

    @throttle.limit_refresh(15)
    def get_wifi_status(self):
        if not self.is_wifi_enabled():
            return WifiStatus.OFF

        if self.get_ip_addr_text() in [
            Language.label("wifiStatusOff", "Off"),
            Language.label("wifiStatusError", "Error"),
            Language.label("wifiStatusConnecting", "Connecting"),
        ]:
            return WifiStatus.OFF

        info = self.get_wifi_connection_quality_info()

        # RSSI in dBm (negative values)
        rssi = info.signal_level

        # Missing / invalid RSSI
        if rssi is None or rssi <= -200:
            return WifiStatus.OFF

        # Keep network state synced
        self.get_ip_addr_text()

        # RSSI-based classification
        if rssi >= -50:
            return WifiStatus.GREAT      # Excellent
        elif rssi >= -67:
            return WifiStatus.GOOD       # Strong / stable
        elif rssi >= -75:
            return WifiStatus.OKAY       # Usable
        else:
            return WifiStatus.BAD        # Weak / unreliable

        
    def get_running_processes(self):
        #bypass ProcessRunner.run_and_print() as it makes the log too big
        return subprocess.run(['ps', '-f'], capture_output=True, text=True)


    def start_udhcpc(self):
        try:
            # Check if wpa_supplicant is running using ps -f
            result = self.get_running_processes()
            if 'udhcpc' in result.stdout:
                return

            # If not running, start it in the background
            subprocess.Popen([
                'udhcpc',
                '-i', 'wlan0'
            ])
            time.sleep(0.5)  # Wait for it to initialize
            PyUiLogger.get_logger().info("udhcpc started.")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error starting udhcpc: {e}")

    def start_wifi_services(self, foreground_call=False):
        if not self.connection_seems_up():
            PyUiLogger.get_logger().info("Starting WiFi Services")
            if(foreground_call):
                Display.display_message(Language.label("turningOnWifiPower", "Turning on WiFi Power"))
                
            self.set_wifi_power(1)
            time.sleep(1)  
            if(foreground_call):
                Display.display_message(Language.label("startingWifiProcess", "Starting WiFi process"))
            self.start_wpa_supplicant()
            if(foreground_call):
                Display.display_message(Language.label("startingIpAssignment", "Starting ip address assignment process"))
            self.start_udhcpc()

    # spruce's networkservices.sh starts Samba, SSH, SFTPGo, Syncthing and the
    # landing page, and syncs the clock, once the network is actually up. It runs
    # from principal.sh at boot and again on every return to the menu from a game -
    # but PyUI brings WiFi up through its own Python path, so turning WiFi on from
    # the menu left all of that waiting for the next game exit. The clock is the
    # worst of it: until it is set, every HTTPS request fails as "certificate not
    # yet valid", because these devices have no battery-backed RTC.
    #
    # Safe to fire and forget. The script waits for the connection itself, so
    # calling it before wlan0 has an address is fine; it holds a lock so a second
    # copy exits immediately; and it skips services that are already running.
    # Detached, because it blocks until the network appears.
    NETWORK_SERVICES_SCRIPT = "/mnt/SDCARD/spruce/scripts/networkservices.sh"

    def _run_network_services(self, *args):
        if not os.path.exists(self.NETWORK_SERVICES_SCRIPT):
            # Not a spruce userland (muOS, Rocknix) - nothing of ours to start.
            return
        try:
            subprocess.Popen(
                [self.NETWORK_SERVICES_SCRIPT, *args],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to launch networkservices.sh: {e}")

    def start_network_services(self):
        self._run_network_services()

    def stop_network_services(self):
        self._run_network_services("off")


    def wifi_connect(self, ssid: str, password):
        """Apply a network selection. password is None for an open network.

        Default is the wpa_supplicant behaviour the WiFi menu used to do inline:
        write a network block to wpa_supplicant.conf and tell wpa_cli to reload.
        Hosts that manage WiFi another way (NetworkManager on the RGB30, connman
        on the GKD Pixel 2) override this.
        """
        from devices.utils.process_runner import ProcessRunner
        conf_path = self.get_wpa_supplicant_conf_path()
        if password is None:
            pw_line = "key_mgmt=NONE"
        else:
            pw_line = 'psk="' + password + '"'
        self._write_wpa_supplicant_block(conf_path, ssid, pw_line)
        try:
            ProcessRunner.run(["wpa_cli", "reconfigure"])
        except Exception as e:
            PyUiLogger.get_logger().error(f"wpa_cli reconfigure failed: {e}")

    def _write_wpa_supplicant_block(self, file_path, ssid, pw_line):
        try:
            try:
                with open(file_path, "r") as f:
                    lines = f.readlines()
            except FileNotFoundError:
                lines = []

            header_lines = []
            networks = []
            current_block = []
            in_block = False
            for line in lines:
                stripped = line.strip()
                if stripped.startswith("network={"):
                    in_block = True
                    current_block = [line]
                elif in_block:
                    current_block.append(line)
                    if stripped == "}":
                        networks.append(current_block)
                        current_block = []
                        in_block = False
                else:
                    header_lines.append(line)

            # Written raw, deliberately - wpa_supplicant does no backslash
            # unescaping in plain quoted strings.
            new_block = ["network={\n", f'    ssid="{ssid}"\n', f"    {pw_line}\n", "}\n"]

            # Drop any existing block for this ssid, then append the new one.
            kept = []
            for block in networks:
                if not any(f'ssid="{ssid}"' in bl for bl in block):
                    kept.append(block)
            with open(file_path, "w") as f:
                for line in header_lines:
                    f.write(line)
                for block in kept:
                    f.write("\n")
                    for line in block:
                        f.write(line)
                f.write("\n")
                for line in new_block:
                    f.write(line)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to write wpa_supplicant.conf: {e}")

    @throttle.limit_refresh(10)
    def get_ip_addr_text(self):
        import subprocess

        if not self.is_wifi_enabled():
            return Language.label("wifiStatusOff", "Off")

        try:
            # Query interface address
            result = subprocess.run(
                ["ip", "-4", "addr", "show", "wlan0"],
                capture_output=True,
                text=True
            )

            output = result.stdout

            # Look for "inet x.x.x.x"
            for line in output.splitlines():
                line = line.strip()
                if line.startswith("inet "):
                    return line.split()[1].split("/")[0]

            return Language.label("wifiStatusConnecting", "Connecting")

        except Exception:
            return Language.label("wifiStatusError", "Error")    

    def exit_pyui(self):
        Display.deinit_display()
        sys.exit()

    def double_init_sdl_display(self):
        return False

    def supports_volume(self):
        return True
        
    def get_text_width_measurement_multiplier(self):
        return 1
        
    def max_texture_width(self):
        #No known limit?
        return sys.maxsize
        
    def max_texture_height(self):
        #No known limit?
        return sys.maxsize
        
    def get_guaranteed_safe_max_text_char_count(self):
        return 35

    def get_system_config(self):
        return self.system_config
    
    def supports_popup_menu(self):
        return True
    
    # spruce ships its own copy of the tz database. The Miyoo Mini has none at
    # all and a read-only squashfs root, so there is nowhere to install one, and
    # the devices that do have a firmware copy disagree about which zones they
    # carry. Shipping it means every device offers the same list.
    SPRUCE_ZONEINFO_DIR = "/mnt/SDCARD/spruce/zoneinfo"

    def get_zoneinfo_dir(self):
        return DeviceCommon.SPRUCE_ZONEINFO_DIR

    def supports_timezone_setting(self):
        return os.path.isdir(self.get_zoneinfo_dir())

    def apply_timezone(self, timezone):
        """
        Point this process at the chosen zone and make it take effect now.

        glibc reads a tz file from any absolute path when TZ starts with a
        colon, which is what lets this work with the database on the SD card
        rather than in /etc. tzset() republishes it to the C library, so the
        clock is right immediately instead of after a reboot, and anything
        launched from here inherits TZ through the environment.
        """
        zone_file = os.path.join(self.get_zoneinfo_dir(), timezone)

        if not os.path.isfile(zone_file):
            PyUiLogger.get_logger().error(f"No tz file for {timezone} at {zone_file}")
            return False

        os.environ["TZ"] = f":{zone_file}"
        time.tzset()
        PyUiLogger.get_logger().info(f"Applied timezone {timezone} from {zone_file}")
        return True

    def restore_saved_timezone(self):
        """
        Re-apply the saved zone at start up. TZ lives in this process's
        environment and nowhere else, so it has to be set again every launch.
        Quiet when nothing is saved yet -- that is a normal first boot.

        This deliberately calls the shared implementation rather than whatever
        the device overrode apply_timezone with. Those overrides write files the
        rest of the system reads, and that work belongs to the moment the user
        picks a zone, not to every launch -- on the Pixel 2 the override even
        restarts a service. All that is needed here is TZ.
        """
        if not os.path.isdir(self.get_zoneinfo_dir()):
            return

        try:
            system_config = self.get_system_config()
            # Only a zone the user actually chose. get_timezone() falls back to
            # America/New_York, and applying that to a device whose owner never
            # touched the setting would drag a correct clock hours off.
            if not getattr(system_config, "has_timezone", lambda: False)():
                return
            timezone = system_config.get_timezone()
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Could not read saved timezone: {e}")
            return

        if timezone:
            DeviceCommon.apply_timezone(self, timezone)

    def set_theme(self, theme_path):
        pass

    def get_core_name_overrides(self, core_name):
        return [core_name]
    
    def get_core_for_game(self, game_system_config, rom_file_path):
        return None

    def prompt_timezone_update(self):
        from menus.settings.timezone_menu import TimezoneMenu

        if not self.supports_timezone_setting():
            PyUiLogger.get_logger().warning(
                f"No timezone database at {self.get_zoneinfo_dir()}")
            return

        timezone_menu = TimezoneMenu()
        tz = timezone_menu.ask_user_for_timezone(
            timezone_menu.list_timezone_files(self.get_zoneinfo_dir(),
                                              verify_via_datetime=True))

        if tz is not None:
            self.get_system_config().set_timezone(tz)
            self.apply_timezone(tz)

    def supports_caching_rom_lists(self):
        return True

    def get_saves_dir(self):
        return "/mnt/SDCARD/Saves/"

    def keep_running_on_error(self):
        return True

    def get_boxart_small_resize_dimensions(self):
        return 640, 480

    def get_boxart_medium_resize_dimensions(self):
        return 640, 480

    def get_boxart_large_resize_dimensions(self):
        return 640, 480

    def supports_qoi(self):
        return True

    def set_disp_red(self,value):
        self.system_config.reload_config()
        self.system_config.set_disp_red(value)
        self.system_config.save_config()
        self._set_disp_red_to_config()

    def set_disp_blue(self,value):
        self.system_config.reload_config()
        self.system_config.set_disp_blue(value)
        self.system_config.save_config()
        self._set_disp_blue_to_config()

    def set_disp_green(self,value):
        self.system_config.reload_config()
        self.system_config.set_disp_green(value)
        self.system_config.save_config()
        self._set_disp_green_to_config()

    def supports_rgb_calibration(self):
        return False
    
    def _set_disp_red_to_config(self):
        pass

    def _set_disp_blue_to_config(self):
        pass

    def _set_disp_green_to_config(self):
        pass

    def get_disp_red(self):
        return self.system_config.get_disp_red()

    def get_disp_blue(self):
        return self.system_config.get_disp_blue()

    def get_disp_green(self):
        return self.system_config.get_disp_green()

    def get_audio_system(self):
        return AudioPlayerNone()

    def get_extra_settings_options(self):
        return []
    
    def get_device_specific_about_info_entries(self):
        return []

    def get_mac_address(self,iface="wlan0"):
        try:
            with open(f"/sys/class/net/{iface}/address") as f:
                return f.read().strip()
        except Exception as e:
            PyUiLogger.get_logger().error(f"Could not read MAC address for interface {iface} : {e}")
            return Language.label("aboutUnknown", "Unknown")

    def get_fw_version(self):
        return Language.label("aboutUnknown", "Unknown")

    def get_about_info_entries(self):
        about_info_entries = []
        about_info_entries.append( (Language.label("aboutIpAddress", "IP Address"), self.get_ip_addr_text()) )
        about_info_entries.append( (Language.label("aboutMacAddress", "Mac Address"), self.get_mac_address()) )
        about_info_entries.append( (Language.label("aboutFwVersion", "FW Version"),self.get_fw_version()) )
        about_info_entries.extend(self.get_device_specific_about_info_entries())
        return about_info_entries
    
    def startup_init(self, include_wifi):
        pass

    def might_require_surface_format_conversion(self):
        return False

    def _load_system_config(self, config_path, config_if_missing):
        ConfigCopier.ensure_config(config_path, config_if_missing)

        try:
            self.system_config = DeviceUserConfig(config_path)
        except Exception as e:
            logger = PyUiLogger.get_logger()
            logger.error(f"Failed to load system config, backing up and resetting config: {e}")

            config_path = Path(config_path)
            bak_path = config_path.with_suffix(config_path.suffix + ".bak")

            try:
                os.replace(config_path, bak_path)  # overwrites existing .bak
            except FileNotFoundError:
                pass  # config may not exist; ignore

            ConfigCopier.ensure_config(config_path, config_if_missing)
            self.system_config = DeviceUserConfig(config_path)


    def is_filesystem_read_only(self,path="/mnt/SDCARD"):
        try:
            with tempfile.NamedTemporaryFile(dir=path, delete=True):
                pass
            return False
        except OSError:
            return True

    def perform_sdcard_ro_check(self):
        if self.is_filesystem_read_only("/mnt/SDCARD"):
            Display.display_message(Language.label("sdcardReadOnlyWarning", "Warning: /mnt/SDCARD is read-only. Please check your SD card."), duration_ms=10000)

    def sync_hw_clock(self):
        #Is this different per device? Should be right for the tina linux handhelds at least
        try:
            subprocess.run(
                ["hwclock", "-w", "-u"],
                check=True
            )
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to run hwclock: {e}")

    SPRUCE_HELPER_FUNCTIONS = "/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

    def _apply_spruce_cpu_mode(self, shell_function):
        """
        Hand off to the shell's CPU mode functions, which already know each
        platform's cores and frequencies. Devices without them fall back to
        set_smart via platform/device.sh, so this is safe everywhere.
        """
        if not os.path.exists(self.SPRUCE_HELPER_FUNCTIONS):
            return

        try:
            subprocess.run(
                ["/bin/sh", "-c", f". {self.SPRUCE_HELPER_FUNCTIONS} && {shell_function}"],
                check=False,
                timeout=10
            )
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Could not apply CPU mode {shell_function}: {e}")

    def set_cpu_low_power(self):
        """Drop to the platform's powersave profile while the device sits idle."""
        self._apply_spruce_cpu_mode("set_powersave")

    def set_cpu_normal(self):
        """Back to the mode the menu normally runs in."""
        self._apply_spruce_cpu_mode("set_smart")

    def animation_divisor(self):
        return self.get_system_config().animation_speed(1)

    def get_wifi_menu(self):
        return WifiMenu()

    def get_new_wifi_scanner(self):
        return WiFiScanner()

    def post_present_operations(self):
        # Uneeded for most devices
        pass

    def get_free_mem_mb(self,free_mem_variable):
        with open("/proc/meminfo", "r") as f:
            meminfo = f.read()

        for line in meminfo.splitlines():
            if line.startswith(free_mem_variable+":"):
                # value is in kB
                return int(line.split()[1]) // 1024

        
        return None

    def clear_display_cache_if_memory_full(self, free_mem_variable, threshold_mb):
        # last cache clear is done to account for the time it takes
        # the memory to truly become free after we've marked it for deletion
        # in SDL
        self.last_cache_clear += 1
        free_mb = self.get_free_mem_mb(free_mem_variable)

        if free_mb is not None and free_mb < threshold_mb and self.last_cache_clear > 10:
            PyUiLogger.get_logger().warning(f"Low memory detected: {free_mb} MB available, clearing display cache.")
            Display.clear_cache(include_fonts=False)
            self.last_cache_clear = 0

    def get_image_for_activity(self, activity):
        # Implement in child classes where possible
        return None
    

    def fix_sleep_sound_bug(self):
        pass

    def uses_deinit_v2(self):
        # Need to test 1 at a time to ensure it works
        return False

    def wants_gles_context(self):
        """
        Ask SDL for an OpenGL ES EGL config rather than a desktop GL one.

        On KMSDRM, SDL picks the EGL config for its window from
        gl_config.profile_mask. Left at the default it asks for
        EGL_OPENGL_BIT, and a GPU that only does GLES advertises no such
        config - so eglChooseConfig matches nothing and window creation fails
        with "Can't window GBM/EGL surfaces", naming neither GL nor the
        config as the cause.

        Almost certainly right for every device here, since they are all
        GLES-only ARM parts, but left off by default: the ones that already
        work are not worth risking to tidy this up, and it can be widened per
        device as each is actually tested.
        """
        return False
    
    def get_device_names(self):
        """Every name this device answers to in a config "devices" list.

        Almost every device answers to exactly one - its model name. A
        family whose models share a hardware platform overrides this to
        report a family token alongside the model name, so a single config
        entry covers the whole line and a new model needs no config edits.
        """
        return [self.get_device_name()]

    def get_selected_emulator(self, menu_options: dict):
        for key, option in menu_options.items():
            if key.startswith("Emulator"):
                devices = option.get("devices", [])
                if any(name in devices for name in self.get_device_names()):
                    return option.get("selected")
        if menu_options.get("Emulator"):
            return menu_options["Emulator"].get("selected")
        return None
    
    def check_for_button_remap(self, input):
        return self.button_remapper.get_mappping(input)

    def capture_framebuffer(self):
        pass

    def restore_framebuffer(self):
        pass

    def clear_framebuffer(self):
        pass

    def are_headphones_plugged_in(self):
        return False
        
    def get_image_utils(self):
        return FfmpegImageUtils()


    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        return False
    
    def is_lid_closed(self):
        return False
    
    def map_key(self, key_code):
        PyUiLogger.get_logger().debug(f"Unrecognized keycode {key_code}")
        return None

    def get_game_images_folder_name(self):
        return "Imgs"
