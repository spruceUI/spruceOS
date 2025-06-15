

import socket
import subprocess
import time
from controller.controller_inputs import ControllerInput
from devices.abstract_device import AbstractDevice
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_status import WifiStatus
from display.font_purpose import FontPurpose
from utils import throttle
from utils.logger import PyUiLogger
import psutil


class DeviceCommon(AbstractDevice):

    def prompt_power_down(self):
        from display.display import Display
        from themes.theme import Theme
        from controller.controller import Controller
        while(True):
            PyUiLogger.get_logger().info("Prompting for shutdown")
            Display.clear("Power")
            Display.render_text_centered(f"Would you like to power down?",self.screen_width//2, self.screen_height//2,Theme.text_color(FontPurpose.LIST), purpose=FontPurpose.LIST)
            Display.render_text_centered(f"A = Power Down, X = Reboot, B = Cancel",self.screen_width //2, self.screen_height//2+100,Theme.text_color(FontPurpose.LIST), purpose=FontPurpose.LIST)
            Display.present()
            if(Controller.get_input()):
                if(Controller.last_input() == ControllerInput.A):
                    self.run_app([self.power_off_cmd])
                elif(Controller.last_input() == ControllerInput.X):
                    self.run_app([self.reboot_cmd])
                elif(Controller.last_input() == ControllerInput.B):
                    return

    @property
    def input_timeout_default(self):
        return 1/12 # 12 fps
    
    @property
    def screen_rotation(self):
        return 0

    def map_backlight_from_10_to_full_255(self,lumination_level):
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
            return 1
        
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

    @property
    def hue(self):
        return self.system_config.get_hue()
    
    @property
    def lumination(self):
        return self.system_config.backlight
    
    @property
    def contrast(self):
        return self.system_config.get_contrast()

    @property
    def brightness(self):
        return self.system_config.get_brightness()
    
    @property
    def saturation(self):
        return self.system_config.get_saturation()

    def change_volume(self, amount):
        self._set_volume(self.get_volume() + amount)

    def get_display_volume(self):
        return self.get_volume()
            
    def restart_wifi_services(self):
        PyUiLogger.get_logger().info("Restarting WiFi services")
        self.stop_wifi_services()
        self.start_wifi_services()

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
                    self.restart_wifi_services()
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

    @throttle.limit_refresh(10)
    def get_wifi_status(self):
        if(self.is_wifi_enabled()):
            wifi_connection_quality_info = self.get_wifi_connection_quality_info()
            # Composite score out of 100 based on weighted contribution
            # Adjust weights as needed based on empirical testing
            score = (
                (wifi_connection_quality_info.link_quality / 70.0) * 0.5 +          # 50% weight
                (wifi_connection_quality_info.signal_level / 70.0) * 0.3 +        # 30% weight
                ((70 - wifi_connection_quality_info.noise_level) / 70.0) * 0.2    # 20% weight (less noise is better)
            ) * 100

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
        PyUiLogger.get_logger().info("Starting WiFi Services")
        self.set_wifi_power(0)
        time.sleep(1)  
        self.set_wifi_power(1)
        time.sleep(1)  
        self.start_wpa_supplicant()
        self.start_udhcpc()


    @throttle.limit_refresh(15)
    def get_ip_addr_text(self):
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
    