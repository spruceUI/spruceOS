import tempfile
import time
from asyncio import sleep
import json
from pathlib import Path
import subprocess
import threading
import os
from controller.key_watcher_controller import DictKeyMappingProvider, KeyWatcherController
from utils.logger import PyUiLogger
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.miyoo.mini.miyoo_mini_flip_shared_memory_writer import MiyooMiniFlipSharedMemoryWriter
from devices.miyoo.mini.miyoo_mini_flip_specific_model_variables import MiyooMiniSpecificModelVariables
from devices.miyoo.miyoo_device import MiyooDevice
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo.system_config import SystemConfig
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.file_watcher import FileWatcher
from devices.utils.process_runner import ProcessRunner
from menus.games.utils.rom_info import RomInfo
from utils import throttle
from utils.config_copier import ConfigCopier
from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.py_ui_config import PyUiConfig
from utils.time_logger import log_timing

MAX_VOLUME = 20
MIN_RAW_VALUE = -60
MAX_RAW_VALUE = 30

MI_AO_SETVOLUME = 0x4008690b
MI_AO_GETVOLUME = 0xc008690c
MI_AO_SETMUTE   = 0x4008690d

class MiyooMiniCommon(MiyooDevice):
    OUTPUT_MIXER = 2
    SOUND_DISABLED = 0


    def __init__(self, device_name, main_ui_mode, miyoo_mini_specific_model_variables: MiyooMiniSpecificModelVariables):

        self.device_name = device_name
        self.miyoo_mini_specific_model_variables = miyoo_mini_specific_model_variables
        self.controller_interface = self.build_controller_interface()

        self._load_system_config("/mnt/SDCARD/Saves/mini-flip-system.json", Path(__file__).resolve().parent  / 'mini-flip-system.json')
        
        if(main_ui_mode):
            self.miyoo_mini_flip_shared_memory_writer = MiyooMiniFlipSharedMemoryWriter()
            self.miyoo_games_file_parser = MiyooGamesFileParser()        
            self.mainui_volume = None
            self.mainui_config_thread, self.mainui_config_thread_stop_event = FileWatcher().start_file_watcher(
                "/appconfigs/system.json", self.on_mainui_config_change, interval=0.2)
            threading.Thread(target=self.startup_init, daemon=True).start()

        super().__init__()

    def on_mainui_config_change(self):
        path = "/appconfigs/system.json"
        if not os.path.exists(path):
            PyUiLogger.get_logger().warning(f"File not found: {path}")
            return

        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)

            old_volume = self.mainui_volume
            self.mainui_volume = data.get("vol")
            if(old_volume != self.mainui_volume):
                from display.display import Display
                Display.volume_changed(self.mainui_volume * 5)

        except Exception as e:
            PyUiLogger.get_logger().warning(f"Error reading {path}: {e}")
            return None

    def startup_init(self, include_wifi=True):
        if(self.is_wifi_enabled()):
            self.start_wifi_services()
        self.on_mainui_config_change()
        self._set_lumination_to_config()
        self._set_contrast_to_config()
        self._set_saturation_to_config()
        self._set_brightness_to_config()
        self.ensure_wpa_supplicant_conf()
        self.init_gpio()
        if(PyUiConfig.enable_button_watchers()):
            from controller.controller import Controller
            #/dev/miyooio if we want to get rid of miyoo_inputd
            # debug in terminal: hexdump  /dev/miyooio
            self.volume_key_watcher = KeyWatcher("/dev/input/event0")
            Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
            volume_key_polling_thread = threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True)
            volume_key_polling_thread.start()

    def build_controller_interface(self):
        key_mappings = {}  
        key_mappings[KeyEvent(1, 57, 0)] = [InputResult(ControllerInput.A, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 57, 1)] = [InputResult(ControllerInput.A, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 29, 0)] = [InputResult(ControllerInput.B, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 29, 1)] = [InputResult(ControllerInput.B, KeyState.PRESS)]   
        key_mappings[KeyEvent(1, 56, 0)] = [InputResult(ControllerInput.Y, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 56, 1)] = [InputResult(ControllerInput.Y, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 42, 0)] = [InputResult(ControllerInput.X, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 42, 1)] = [InputResult(ControllerInput.X, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 28, 0)] = [InputResult(ControllerInput.START, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 28, 1)] = [InputResult(ControllerInput.START, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 97, 0)] = [InputResult(ControllerInput.SELECT, KeyState.RELEASE)]   
        key_mappings[KeyEvent(1, 97, 1)] = [InputResult(ControllerInput.SELECT, KeyState.PRESS)]   

        key_mappings[KeyEvent(1, 1, 0)] = [InputResult(ControllerInput.MENU, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 1, 1)] = [InputResult(ControllerInput.MENU, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 15, 0)] = [InputResult(ControllerInput.L2, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 15, 1)] = [InputResult(ControllerInput.L2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 20, 0)] = [InputResult(ControllerInput.R1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 20, 1)] = [InputResult(ControllerInput.R1, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 14, 0)] = [InputResult(ControllerInput.R2, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 14, 1)] = [InputResult(ControllerInput.R2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 18, 0)] = [InputResult(ControllerInput.L1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 18, 1)] = [InputResult(ControllerInput.L1, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 103, 1)] = [InputResult(ControllerInput.DPAD_UP, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 103, 0)] = [InputResult(ControllerInput.DPAD_UP, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 108, 1)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 108, 0)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 105, 1)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 105, 0)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 106, 1)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 106, 0)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.RELEASE)]

        
        return KeyWatcherController(event_path="/dev/input/event0", mapping_provider=DictKeyMappingProvider(key_mappings))

    def power_off_cmd(self):
        return self.miyoo_mini_specific_model_variables.poweroff_cmd

    def get_controller_interface(self):
        return self.controller_interface

    def init_gpio(self):
        #self.init_sleep_gpio()
        pass

    def init_sleep_gpio(self):
        try:
            if not os.path.exists("/sys/class/export"):
                with open("/sys/class/gpio/export", "w") as f:
                    f.write("4")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error exporting gpio 4 {e}")


    def are_headphones_plugged_in(self):
        try:
            with open("/sys/class/gpio/gpio150/value", "r") as f:
                value = f.read().strip()
                return "0" == value 
        except (FileNotFoundError, IOError) as e:
            return False
        
    def is_lid_closed(self):
        return False

    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        return False

    def screen_width(self):
        return self.miyoo_mini_specific_model_variables.width

    def screen_height(self):
        return self.miyoo_mini_specific_model_variables.height
        
    def screen_rotation(self):
        return 0
    
    def output_screen_width(self):
        if(self.should_scale_screen()):
            return 1920
        else:
            return self.screen_height()
        
    def output_screen_height(self):
        if(self.should_scale_screen()):
            return 1080
        else:
            return self.screen_width()

    def get_scale_factor(self):
        if(self.is_hdmi_connected()):
            return 2.25
        else:
            return 1
    
    def _update_stock_config(self, key, value):
        path = "/appconfigs/system.json"

        try:
            # Only proceed if file exists
            if not os.path.isfile(path):
                return

            # Load existing JSON (fail silently if invalid)
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)

            # Only update if it's a dict
            if not isinstance(data, dict):
                return

            # Update saturation
            data[key] = value

            # Atomic write back to same file
            dir_name = os.path.dirname(path) or "."
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=dir_name,
                delete=False
            ) as tmp:
                json.dump(data, tmp, indent=2)
                tmp.flush()
                os.fsync(tmp.fileno())
                tmp_path = tmp.name

            os.replace(tmp_path, path)

        except Exception:
            # Silently ignore all failures
            pass

    def _set_lumination_to_config(self):
        # Miyoo internally has lumination but it does not work
        self._update_stock_config("brightness", self.system_config.backlight)
        self.miyoo_mini_flip_shared_memory_writer.set_brightness(self.system_config.backlight)

    def _set_contrast_to_config(self):
        self._update_stock_config("contrast", self.system_config.contrast)
    
    def _set_saturation_to_config(self):
        #Doesn't seem to work?
        self._update_stock_config("saturation", self.system_config.saturation)

    def _set_brightness_to_config(self):
        #Doesn't seem to work?
        self._update_stock_config("lumination", self.system_config.brightness)

    def _set_hue_to_config(self):
        pass
    
    def take_snapshot(self, path):
        return None
    
    @throttle.limit_refresh(15)
    def get_ip_addr_text(self):
        if self.miyoo_mini_specific_model_variables.supports_wifi:
            if self.is_wifi_enabled():
                try:
                    # Run the system command to get wlan0 info
                    result = subprocess.run(
                        ["ip", "addr", "show", "wlan0"],
                        capture_output=True,
                        text=True
                    )

                    if result.returncode != 0:
                        return "Error"

                    # Look for an IPv4 address in the command output
                    for line in result.stdout.splitlines():
                        line = line.strip()
                        if line.startswith("inet "):  # Example: "inet 192.168.1.42/24 ..."
                            ip = line.split()[1].split("/")[0]  # Take "192.168.1.42" part
                            return ip

                    return "Connecting"  # wlan0 exists but no IP yet

                except Exception:
                    return "Error"

            return "Off"
        else:
            return "Unsupported"

    def supports_wifi(self):
        return self.miyoo_mini_specific_model_variables.supports_wifi

    def get_charge_status(self):
        return self.miyoo_mini_specific_model_variables.get_charge_status()

    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        return self.miyoo_mini_specific_model_variables.get_battery_percent()
    

    def start_wifi_services(self):
        if(self.miyoo_mini_specific_model_variables.supports_wifi):
            try:
                # Check if system already has an IP address
                result = subprocess.run(
                    ["ip", "route", "get", "1"],
                    capture_output=True,
                    text=True
                )

                # Extract the last field (the IP) like `awk '{print $NF;exit}'`
                parts = result.stdout.strip().split()
                ip = parts[-1] if parts else ""

                if not ip:
                    PyUiLogger.get_logger().info("Wifi is disabled - trying to enable it...")

                    subprocess.run(["insmod", "/mnt/SDCARD/8188fu.ko"])
                    subprocess.run(["ifconfig", "lo", "up"])
                    subprocess.run(["/customer/app/axp_test", "wifion"])
                    time.sleep(2)
                    subprocess.run(["ifconfig", "wlan0", "up"])
                    subprocess.run([
                        "wpa_supplicant",
                        "-B",
                        "-D", "nl80211",
                        "-i", "wlan0",
                        "-c", self.get_wpa_supplicant_conf_path()
                    ])
                    subprocess.run(["udhcpc", "-i", "wlan0", "-s", "/etc/init.d/udhcpc.script"])
                    time.sleep(3)
                    os.system("clear")

            except Exception as e:
                PyUiLogger.get_logger().error(f"Error enabling WiFi: {e}")


    def set_wifi_power(self, value):
        if(self.miyoo_mini_specific_model_variables.supports_wifi):
            if(0 == value):
                ProcessRunner.run(["ifconfig", "wlan0", "down"])

    def get_bluetooth_scanner(self):
        return None
        
    def reboot_cmd(self):
        return self.miyoo_mini_specific_model_variables.reboot_cmd

    def get_wpa_supplicant_conf_path(self):
        return PyUiConfig.get_wpa_supplicant_conf_file_location("/appconfigs/wpa_supplicant.conf")

    def get_volume(self):
        try:
            return self.mainui_volume * 5
        except:
            return 0

    def volume_up(self):
        try:
            subprocess.run(
                ["send_event", "/dev/input/event0", "115:1"],
                check=False
            )
        except Exception as e:
            PyUiLogger.get_logger().exception(f"Failed to set volume via input events: {e}")

    def volume_down(self):
        try:
            subprocess.run(
                ["send_event", "/dev/input/event0", "114:1"],
                check=False
            )
        except Exception as e:
            PyUiLogger.get_logger().exception(f"Failed to set volume via input events: {e}")

    def change_volume(self, amount):
        self.system_config.reload_config()
        volume = self.get_volume() + amount
        if(volume < 0):
            volume = 0
        elif(volume > 100):
            volume = 100
        if(amount > 0):
            self.volume_up()
        else:
            self.volume_down()
        sleep(0.1)
        self.on_mainui_config_change()

    def _set_volume(self, volume: int) -> int:
        event_dev = "/dev/input/event0"

        try:
            # Send volume-down (114) 20 times
            for _ in range(20):
                subprocess.run(
                    ["send_event", event_dev, "114:1"],
                    check=False
                )
            time.sleep(0.2)
            # Send volume-up (115) volume//5 times
            for _ in range(volume // 5):
                subprocess.run(
                    ["send_event", event_dev, "115:1"],
                    check=False
                )

        except Exception as e:
            PyUiLogger.get_logger().exception(f"Failed to set volume via input events: {e}")

        return volume

    def fix_sleep_sound_bug(self):
        pass #uneeded


    def run_game(self, rom_info: RomInfo) -> subprocess.Popen:
        preload_path = "/mnt/SDCARD/miyoo/app/../lib/libpadsp.so"
        if os.path.exists(preload_path):
            run_prefix = f"LD_PRELOAD={preload_path} "
        else:
            run_prefix = "LD_PRELOAD=/customer/lib/libpadsp.so "
        return MiyooTrimCommon.run_game(self, rom_info, run_prefix=run_prefix)

    def double_init_sdl_display(self):
        return True
            
    def max_texture_width(self):
        return 800
                    
    def max_texture_height(self):
        return 600

    def get_guaranteed_safe_max_text_char_count(self):
        return 35

    def supports_volume(self):
        return True #can read but not write

    def supports_analog_calibration(self):
        return False

    def supports_image_resizing(self):
        return True

    def supports_brightness_calibration(self):
        return True

    def supports_contrast_calibration(self):
        return True

    def supports_saturation_calibration(self):
        return True

    def supports_hue_calibration(self):
        return False
    
    def supports_popup_menu(self):
        return False
    
    def get_image_utils(self):
        return FfmpegImageUtils()

    def get_boxart_small_resize_dimensions(self):
        return 400,300

    def get_boxart_medium_resize_dimensions(self):
        return 400,300

    def get_boxart_large_resize_dimensions(self):
        return 400,300
    
    def get_device_name(self):
        return self.device_name
    
    def supports_timezone_setting(self):
        return True

    def prompt_timezone_update(self):
        #No timezone update for miyoo mini
        pass

    def apply_timezone(self, timezone):
        ProcessRunner.run(["rm", "-f", "/tmp/localtime"])
        ProcessRunner.run(["ln", "-s", "/mnt/SDCARD/miyoo285/zoneinfo/"+timezone ,"/tmp/localtime"])

    def supports_caching_rom_lists(self):
        return True #Is there enough RAM

    
    def get_fw_version(self):
        try:
            # Run fw_printenv and capture output
            result = subprocess.run(
                ["/etc/fw_printenv", "miyoo_version"],
                capture_output=True,
                text=True,
                check=True
            )
            
            output = result.stdout.strip()

            # Expected format: "miyoo_version=202510011046"
            if "=" in output:
                return output.split("=", 1)[1].strip()

            return output
        except Exception as e:
            PyUiLogger.get_logger().error(f"Could not read FW version : {e}")
            return "Unknown"

    def get_core_for_game(self, game_system_config, rom_file_path):
        core = game_system_config.get_effective_menu_selection("Emulator_MiyooMini", rom_file_path)
        if(core is None):
            core = game_system_config.get_effective_menu_selection("Emulator", rom_file_path)
        return core
    
    def get_core_name_overrides(self, core_name):
        return [core_name, core_name+"-32"]


    def animation_divisor(self):
        return self.get_system_config().animation_speed(2) 
