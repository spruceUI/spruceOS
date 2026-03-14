from pathlib import Path
import re
import subprocess
import threading
from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from devices.charge.charge_status import ChargeStatus
import os
from devices.device_common import DeviceCommon
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from devices.wifi.wifi_status import WifiStatus
from display.display import Display
from games.utils.device_specific.miyoo_trim_game_system_utils import MiyooTrimGameSystemUtils
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from menus.settings.button_remapper import ButtonRemapper
from utils import throttle
from utils.logger import PyUiLogger
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller import DictKeyMappingProvider, KeyWatcherController
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.miyoo.flip.miyoo_flip_poller import MiyooFlipPoller
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.utils.process_runner import ProcessRunner
from utils import throttle
from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

from devices.device_common import DeviceCommon

#/mnt/vendor/ctrl/dmenu_ln
class AnbernicRG34xxSP(DeviceCommon):
    def __init__(self):
        self.device_name = "MIYOO_A30"
 
        script_dir = Path(__file__).resolve().parent
        source = script_dir / 'anbernic-rg34xxsp-system.json'
        self._load_system_config("/mnt/SDCARD/Saves/anbernic-rg34xxsp-system.json", source)
        self.miyoo_games_file_parser = MiyooGamesFileParser()        
        self.hardware_poller = MiyooFlipPoller(self)
        threading.Thread(target=self.hardware_poller.continuously_monitor, daemon=True).start()
        self.game_utils = MiyooTrimGameSystemUtils()

        #self._set_lumination_to_config()
        #self._set_contrast_to_config()
        #self._set_saturation_to_config()
        #self._set_brightness_to_config()
        #self._set_hue_to_config()

        if(PyUiConfig.enable_button_watchers()):
            from controller.controller import Controller
            #/dev/miyooio if we want to get rid of miyoo_inputd
            # debug in terminal: hexdump  /dev/miyooio
            self.volume_key_watcher = KeyWatcher("/dev/input/event0")
            Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
            volume_key_polling_thread = threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True)
            volume_key_polling_thread.start()
            self.power_key_watcher = KeyWatcher("/dev/input/event2")
            power_key_polling_thread = threading.Thread(target=self.power_key_watcher.poll_keyboard, daemon=True)
            power_key_polling_thread.start()
            self.controller_watcher = KeyWatcher("/dev/input/event1")
            Controller.add_button_watcher(self.controller_watcher.poll_keyboard)
            controller_watching_thread = threading.Thread(target=self.controller_watcher.poll_keyboard, daemon=True)
            controller_watching_thread.start()

        self.button_remapper = ButtonRemapper(self.system_config)

    def sleep(self):
        pass #TODO

    def ensure_wpa_supplicant_conf(self):
        pass

    def should_scale_screen(self):
        return self.is_hdmi_connected()

    
    def power_off_cmd(self):
        return "poweroff"
    
    
    def reboot_cmd(self):
        return "reboot"

    def _set_brightness_to_config(self):
        pass
                   
    def _set_lumination_to_config(self):
        import fcntl
        import struct
        DEV = "/dev/disp"
        IOCTL_SET_BRIGHTNESS = 0x102
        val = self.map_backlight_from_10_to_full_255(self.system_config.backlight)

        # 4 unsigned long values (ARM64 = 8 bytes each)
        args = struct.pack("QQQQ", 0, val, 0, 0)

        fd = os.open(DEV, os.O_RDWR)
        try:
            fcntl.ioctl(fd, IOCTL_SET_BRIGHTNESS, args)
        finally:
            os.close(fd)     

    def _set_contrast_to_config(self):
        pass
    
    def _set_saturation_to_config(self): 
        pass


    def _set_hue_to_config(self):
        # echo val > /sys/class/disp/disp/attr/color_temperature
        pass

    def get_volume(self):
        return self.system_config.get_volume()
    
    def run_game(self, rom_info: RomInfo):
        from controller.controller import Controller
        menu_options = rom_info.game_system.game_system_config.get_menu_options()
        selected_core = self.get_selected_emulator(menu_options, self.device_name)
        if(selected_core is None):
            Display.display_message("No core found", 2_000)
            return

        selected_core = "/mnt/SDCARD/RetroArch/.retroarch/cores64/" + selected_core + "_libretro.so"
        
        cmds = ["/mnt/SDCARD/RetroArch/ra64.universal",
                "--config", "/mnt/SDCARD/RetroArch/platform/retroarch-AnbernicRG34XXSP.cfg",
                "-v",
                "--log-file","/mnt/SDCARD/Saves/spruce/retroarch.log",
                "-L",selected_core,
                rom_info.rom_file_path]

        directory = "/mnt/SDCARD/RetroArch/"
        PyUiLogger.get_logger().debug(f"About to launch {cmds} from dir {directory}")
        Display.deinit_display()
        subprocess.run(cmds, cwd = directory)
        Display.init()

        Controller.clear_input_queue()

    def run_cmd(self, args, dir = None):
        MiyooTrimCommon.run_cmd(self, args, dir)
            
    def run_app(self, folder,launch):
        from controller.controller import Controller
        directory = os.path.dirname(launch)
        Display.deinit_display()
        PyUiLogger.get_logger().debug(f"About to launch app {launch} from dir {directory}")
        subprocess.run([launch], cwd = directory)
        Display.init()
        Controller.clear_input_queue()
    
    def map_digital_input(self, sdl_input):
        return None

    def map_analog_input(self, sdl_axis, sdl_value):
        return None

    def prompt_power_down(self):
        DeviceCommon.prompt_power_down(self)

    def _set_volume(self, volume):
        #TODO
        return volume 
    
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
        return WiFiConnectionQualityInfo(noise_level=0, signal_level=0, link_quality=0)

    def is_wifi_enabled(self):
        return self.system_config.is_wifi_enabled()

    @throttle.limit_refresh(5)
    def get_charge_status(self):
        status_file = Path("/sys/class/power_supply/axp2202-battery/status")
        try:
            status = status_file.read_text().strip().lower()
            if status == "charging":
                return ChargeStatus.CHARGING
            else:
                return ChargeStatus.DISCONNECTED
        except:
            # battery info not available
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
        return False # TODO
    
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
        return "/mnt/SDCARD/Saves/pyui-state.json"

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
    
    def get_roms_dir(self):
        return "/mnt/union/ROMS/"
    
    
    def screen_width(self):
        return 720

    
    def screen_height(self):
        return 480
    
    
    def screen_rotation(self):
        return 0

    
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
    
    def take_snapshot(self, path):
        return None
    
    def get_save_state_image(self, rom_info: RomInfo):
        #TODO, where does it store this?
        return None

    def get_wpa_supplicant_conf_path(self):
        return None

    def supports_brightness_calibration(self):
        return False

    def supports_contrast_calibration(self):
        return False

    def supports_saturation_calibration(self):
        return False

    def supports_hue_calibration(self):
        return False

    def supports_qoi(self):
        return False

    def keep_running_on_error(self):
        return False

    def get_controller_interface(self):
        key_mappings = {}  
        key_mappings[KeyEvent(1, 304, 0)] = [InputResult(ControllerInput.A, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 304, 1)] = [InputResult(ControllerInput.A, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 305, 0)] = [InputResult(ControllerInput.B, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 305, 1)] = [InputResult(ControllerInput.B, KeyState.PRESS)]   
        key_mappings[KeyEvent(1, 306, 0)] = [InputResult(ControllerInput.Y, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 306, 1)] = [InputResult(ControllerInput.Y, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 307, 0)] = [InputResult(ControllerInput.X, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 307, 1)] = [InputResult(ControllerInput.X, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 311, 0)] = [InputResult(ControllerInput.START, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 311, 1)] = [InputResult(ControllerInput.START, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 310, 0)] = [InputResult(ControllerInput.SELECT, KeyState.RELEASE)]   
        key_mappings[KeyEvent(1, 310, 1)] = [InputResult(ControllerInput.SELECT, KeyState.PRESS)]   

        key_mappings[KeyEvent(1, 312, 0)] = [InputResult(ControllerInput.MENU, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 312, 1)] = [InputResult(ControllerInput.MENU, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 308, 0)] = [InputResult(ControllerInput.L1, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 308, 1)] = [InputResult(ControllerInput.L1, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 314, 0)] = [InputResult(ControllerInput.L2, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 314, 1)] = [InputResult(ControllerInput.L2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 313, 0)] = [InputResult(ControllerInput.L3, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 313, 1)] = [InputResult(ControllerInput.L3, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 309, 0)] = [InputResult(ControllerInput.R1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 309, 1)] = [InputResult(ControllerInput.R1, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 315, 0)] = [InputResult(ControllerInput.R2, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 315, 1)] = [InputResult(ControllerInput.R2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 316, 0)] = [InputResult(ControllerInput.R3, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 316, 1)] = [InputResult(ControllerInput.R3, KeyState.PRESS)]

        key_mappings[KeyEvent(3, 17, 4294967295)] = [InputResult(ControllerInput.DPAD_UP, KeyState.PRESS)]
        key_mappings[KeyEvent(3, 17, 1)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.PRESS)]
        key_mappings[KeyEvent(3, 17, 0)] = [InputResult(ControllerInput.DPAD_UP, KeyState.RELEASE), InputResult(ControllerInput.DPAD_DOWN, KeyState.RELEASE)]
        key_mappings[KeyEvent(3, 16, 4294967295)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.PRESS)]
        key_mappings[KeyEvent(3, 16, 1)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.PRESS)]
        key_mappings[KeyEvent(3, 16, 0)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.RELEASE), InputResult(ControllerInput.DPAD_RIGHT, KeyState.RELEASE)]

        
        return KeyWatcherController(event_path="/dev/input/event1", mapping_provider=DictKeyMappingProvider(key_mappings))


    def are_headphones_plugged_in(self):
        return False
        
    def is_lid_closed(self):
        try:
            with open("/sys/class/power_supply/axp2202-battery/hallkey", "r") as f:
                value = f.read().strip()
                return "0" == value 
        except (FileNotFoundError, IOError) as e:
            return False

    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        # /sys/class/switch/hdmi/state
        # HDMI=0
        # HDMI=1
        return False
    

    def map_key(self, key_code):
        if(114 == key_code):
            return ControllerInput.VOLUME_DOWN
        elif(115 == key_code):
            return ControllerInput.VOLUME_UP
        elif(116 == key_code):
            return ControllerInput.POWER_BUTTON
        else:
            PyUiLogger.get_logger().debug(f"Unrecognized keycode {key_code}")
            return None
        
    def capture_framebuffer(self):
        ProcessRunner.run(["dd", "if=/dev/fb0", f"of=/tmp/fb_backup.raw", "bs=4096"])

    def restore_framebuffer(self):
        ProcessRunner.run(["dd", f"if=/tmp/fb_backup.raw", "of=/dev/fb0", "bs=4096"])

    def clear_framebuffer(self):
        ProcessRunner.run(["dd", "if=/dev/zero", "of=/dev/fb0", "bs=4096"])

    def get_image_utils(self):
        return FfmpegImageUtils()

    def get_device_name(self):
        return self.device_name
    
    def check_for_button_remap(self, input):
        return self.button_remapper.get_mappping(input)


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

    @throttle.limit_refresh(10)
    def get_ip_addr_text(self):
        import socket
        import fcntl
        import struct
        if not self.is_wifi_enabled():
            return "Off"

        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            iface = b"wlan0"  # interface name must be bytes
            ip = fcntl.ioctl(
                sock.fileno(),
                0x8915,  # SIOCGIFADDR
                struct.pack('256s', iface[:15])
            )[20:24]
            return socket.inet_ntoa(ip)
        except OSError:
            return "Connecting"
        except Exception:
            return "Error"
        
             
    def set_wifi_power(self, value):
        pass

    def stop_wifi_services(self):
        pass

    def start_wpa_supplicant(self):
        pass

    def start_udhcpc(self):
        pass

    def start_wifi_services(self):
        pass

    def is_wifi_enabled(self):
        return self.system_config.is_wifi_enabled()

    def disable_wifi(self):
        pass

    def enable_wifi(self):
        pass

    def uses_deinit_v2(self):
        return True
