

import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from audio.audio_player_none import AudioPlayerNone
from controller.controller_inputs import ControllerInput
from devices.abstract_device import AbstractDevice
from devices.miyoo.system_config import SystemConfig
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_scanner import WiFiScanner
from devices.wifi.wifi_status import WifiStatus
from display.display import Display
from display.font_purpose import FontPurpose
from menus.settings.wifi_menu import WifiMenu
from utils import throttle
from utils.config_copier import ConfigCopier
from utils.logger import PyUiLogger


class DeviceCommon(AbstractDevice):

    def prompt_power_down(self):
        from display.display import Display
        from themes.theme import Theme
        from controller.controller import Controller
        while(True):
            PyUiLogger.get_logger().info("Prompting for shutdown")
            Display.clear("Power")
            Display.render_text_centered(f"Would you like to power down?",self.screen_width()//2, self.screen_height()//2,Theme.text_color(FontPurpose.LIST), purpose=FontPurpose.LIST)
            if(self.reboot_cmd() is not None):
                Display.render_text_centered(f"A = Power Down, X = Reboot, B = Cancel",self.screen_width() //2, self.screen_height()//2+100,Theme.text_color(FontPurpose.LIST), purpose=FontPurpose.LIST)
            else:
                Display.render_text_centered(f"A = Power Down, B = Cancel",self.screen_width() //2, self.screen_height()//2+100,Theme.text_color(FontPurpose.LIST), purpose=FontPurpose.LIST)
            Display.present()
            if(Controller.get_input()):
                if(Controller.last_input() == ControllerInput.A):
                    self.power_off()
                elif(Controller.last_input() == ControllerInput.X and self.reboot_cmd is not None):
                    self.reboot()
                elif(Controller.last_input() == ControllerInput.B):
                    return

    def power_off(self):
        self.run_cmd([self.power_off_cmd()])

    def reboot(self):
        self.run_cmd([self.reboot_cmd()])


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
                    self.start_wifi_services()
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
        if(self.is_wifi_enabled()):
            if(self.get_ip_addr_text() in ["Off","Error","Connecting"]):
                return WifiStatus.OFF
            wifi_connection_quality_info = self.get_wifi_connection_quality_info()
            # Composite score out of 100 based on weighted contribution
            # Adjust weights as needed based on empirical testing
            if(wifi_connection_quality_info.link_quality == 0.0 and wifi_connection_quality_info.signal_level == 0.0):
                return WifiStatus.OFF
            else:
                score = (
                    (wifi_connection_quality_info.link_quality / 70.0) * 0.5 +          # 50% weight
                    (wifi_connection_quality_info.signal_level / 70.0) * 0.3 +        # 30% weight
                    ((70 - wifi_connection_quality_info.noise_level) / 70.0) * 0.2    # 20% weight (less noise is better)
                ) * 100

            # Ensure signal and settings stay in sync
            self.get_ip_addr_text()
            
            if score >= 80:
                return WifiStatus.GREAT
            elif score >= 60:
                return WifiStatus.GOOD
            elif score >= 40:
                return WifiStatus.OKAY
            else:
                return WifiStatus.BAD
        else:            
            return WifiStatus.OFF
        
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

    def start_wifi_services(self):
        if not self.connection_seems_up():
            PyUiLogger.get_logger().info("Starting WiFi Services")
            self.set_wifi_power(1)
            time.sleep(1)  
            self.start_wpa_supplicant()
            self.start_udhcpc()


    @throttle.limit_refresh(10)
    def get_ip_addr_text(self):
        import psutil
        if self.is_wifi_enabled():
            try:
                addrs = psutil.net_if_addrs().get("wlan0")
                if addrs:
                    for addr in addrs:
                        if addr.family == socket.AF_INET:
                            return addr.address
                    return "Connecting"
                else:
                    return "Connecting"
            except Exception:
                return "Error"
        
        return "Off"
    

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
    
    def supports_timezone_setting(self):
        return False

    def apply_timezone(self, timezone):
        pass

    def set_theme(self, theme_path):
        pass

    def get_core_name_overrides(self, core_name):
        return [core_name]
    
    def get_core_for_game(self, game_system_config, rom_file_path):
        return None

    def prompt_timezone_update(self):
        #Unsupported by default
        pass

    def supports_caching_rom_lists(self):
        return True

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
            return "Unknown"

    def get_fw_version(self):
        return "Unknown"

    def get_about_info_entries(self):
        about_info_entries = []
        about_info_entries.append( ("IP Address", self.get_ip_addr_text()) )
        about_info_entries.append( ("Mac Address", self.get_mac_address()) )
        about_info_entries.append( ("FW Version",self.get_fw_version()) )
        about_info_entries.extend(self.get_device_specific_about_info_entries())
        return about_info_entries
    
    def startup_init(self, include_wifi):
        pass

    def might_require_surface_format_conversion(self):
        return False

    def _load_system_config(self, config_path, config_if_missing):
        ConfigCopier.ensure_config(config_path, config_if_missing)

        try:
            self.system_config = SystemConfig(config_path)
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
            self.system_config = SystemConfig(config_path)


    def is_filesystem_read_only(self,path="/mnt/SDCARD"):
        try:
            with tempfile.NamedTemporaryFile(dir=path, delete=True):
                pass
            return False
        except OSError:
            return True

    def perform_sdcard_ro_check(self):
        if self.is_filesystem_read_only("/mnt/SDCARD"):
            Display.display_message("Warning: /mnt/SDCARD is read-only. Please check your SD card.", duration_ms=10000)

    def sync_hw_clock(self):
        #Is this different per device? Should be right for the tina linux handhelds at least
        try:
            subprocess.run(
                ["hwclock", "-w", "-u"],
                check=True
            )
        except Exception as e:
            PyUiLogger.get_logger.error(f"Failed to run hwclock: {e}")

    def animation_divisor(self):
        return self.get_system_config().animation_speed(1)

    def get_wifi_menu(self):
        return WifiMenu()

    def get_new_wifi_scanner(self):
        return WiFiScanner()
