from pathlib import Path
import re
import shutil
import subprocess
import threading
import time

from apps.miyoo.miyoo_app_finder import MiyooAppFinder
from controller.controller_inputs import ControllerInput
from devices.charge.charge_status import ChargeStatus
import os
from devices.device_common import DeviceCommon
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.std_in_based_send_event_binary_helper import StdInBasedSendEventBinaryHelper
from devices.utils.file_watcher import FileWatcher
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

# Family token every Anbernic RG XX model answers to in addition to its own
# model name. The XX line is one hardware platform in every way that decides
# whether an app or a setting is offered - same H700 SoC, same controls, same
# userland - so app and emulator configs name this rather than listing each
# model. Models still differ in panel and layout; that stays with the per-model
# classes below (screen_width/screen_height/screen_rotation) and the per-model
# platform cfgs on the shell side.
ANBERNIC_XX_FAMILY = "ANBERNIC_RGXX"


class AnbernicXXCommon(DeviceCommon):
    def __init__(self, main_ui_mode):
        # device_name is set by the subclass before it calls up here. This used
        # to assign a model name unconditionally, which ran *after* the subclass
        # and so made every XX model report itself as that one model - no config
        # "devices" list could tell the models apart.
        script_dir = Path(__file__).resolve().parent
        default_cfg_path = script_dir / 'anbernic-rg-xx-system.json'
        # Shared by the whole XX line on purpose. spruce is built around one card
        # in many devices, so these settings should follow the card rather than
        # stay behind on the device they were set on. The panels differ, so
        # calibration tuned on one is only approximate on another - that is the
        # accepted trade for settings that travel.
        system_cfg_path = "/mnt/SDCARD/Saves/anbernic-rg-xx-system.json"

        # This file was called anbernic-rg34xxsp-system.json until the rename, so
        # on an existing card the new name does not exist yet. Seed it from the
        # old one rather than from the shipped default: that default carries
        # "vol": 0 and set_volume_to_config applies a literal zero, so seeding
        # from it would leave every XX device silent after the update.
        legacy_cfg_path = Path("/mnt/SDCARD/Saves/anbernic-rg34xxsp-system.json")
        if not self._is_usable_config(system_cfg_path) and self._is_usable_config(legacy_cfg_path):
            default_cfg_path = legacy_cfg_path

        self._load_system_config(system_cfg_path, default_cfg_path)
        self.miyoo_games_file_parser = MiyooGamesFileParser()        
        self.game_utils = MiyooTrimGameSystemUtils()

        self._set_lumination_to_config()
        #self._set_contrast_to_config()
        #self._set_saturation_to_config()
        #self._set_brightness_to_config()
        #self._set_hue_to_config()

        if(PyUiConfig.enable_button_watchers()):
            self.hardware_poller = MiyooFlipPoller(self)
            threading.Thread(target=self.hardware_poller.continuously_monitor, daemon=True).start()
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

        if(main_ui_mode):
            # Same point in startup the Miyoo and TrimUI devices do this.
            self.ensure_wpa_supplicant_conf()

            # Done to try to account for external systems editting the config file
            self.config_watcher_thread, self.config_watcher_thread_stop_event = FileWatcher().start_file_watcher(
                system_cfg_path, self.on_system_config_changed, interval=0.2, repeat_trigger_for_mtime_granularity_issues=True)

    @staticmethod
    def _is_usable_config(path):
        # Same test ConfigCopier.ensure_config applies before deciding a config
        # needs seeding, so the two agree about what counts as "already there".
        try:
            path = Path(path)
            return path.exists() and path.stat().st_size > 0
        except OSError:
            return False

    def on_system_config_changed(self):
        old_volume = self.system_config.get_volume()
        self.system_config.reload_config()
        new_volume = self.system_config.get_volume()
        if(old_volume != new_volume):
            Display.volume_changed(new_volume)

    def sleep(self):
        pass #TODO

    def ensure_wpa_supplicant_conf(self):
        # Was a "pass" stub, and nothing called it either, so the file simply
        # never appeared. wpa_supplicant is started with -c pointing at it and
        # refuses to run without it; wpa_cli then has no ctrl socket to talk to,
        # and the scanner - which is nothing but "wpa_cli scan" followed by
        # "wpa_cli scan_results" - returns empty forever. The visible symptom is
        # a device that sits on "Scanning for networks..." and never lists one,
        # with no error anywhere, on any XX device that has never connected.
        MiyooTrimCommon.ensure_wpa_supplicant_conf(self.get_wpa_supplicant_conf_path())

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
        #Is actually 128
        val = self.map_backlight_from_10_to_full_255(self.system_config.backlight) // 2

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
        if(PyUiConfig.mimic_miyoo_mainui_mode()):
            MiyooTrimCommon.run_game(self, rom_info)
        else:
            from controller.controller import Controller
            menu_options = rom_info.game_system.game_system_config.get_menu_options()
            selected_core = self.get_selected_emulator(menu_options)
            if(selected_core is None):
                Display.display_message("No core found", 2_000)
                return

            selected_core = "/mnt/SDCARD/RetroArch/.retroarch/cores64/" + selected_core + "_libretro.so"

            shutil.copyfile("/mnt/SDCARD/RetroArch/platform/retroarch-AnbernicRG_XX-universal.cfg", "/mnt/SDCARD/RetroArch/retroarch.cfg")
            cmds = [
                    "/mnt/SDCARD/RetroArch/ra64.universal",
                    "-v",
                    "--config", "/mnt/SDCARD/RetroArch/retroarch.cfg",
                    "--log-file","/mnt/SDCARD/Saves/spruce/retroarch.log",
                    "-L",selected_core,
                    rom_info.rom_file_path]

            directory = "/mnt/SDCARD/RetroArch/"
            PyUiLogger.get_logger().debug(f"About to launch {cmds} from dir {directory}")
            Display.deinit_display()
            subprocess.run(cmds, cwd = directory)
            Display.init()

            Controller.clear_input_queue()

    def run_cmd(self, args, dir = None, is_power_cmd = False):
        MiyooTrimCommon.run_cmd(self, args, dir, is_power_cmd)
            
    def run_app(self, folder,launch):
        if(PyUiConfig.mimic_miyoo_mainui_mode()):
            MiyooTrimCommon.run_app(self, folder,launch)
        else:
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
        
    def volume_up(self):
        StdInBasedSendEventBinaryHelper.send_key_down_and_up("/dev/input/event1",115)

    def volume_down(self):
        StdInBasedSendEventBinaryHelper.send_key_down_and_up("/dev/input/event1",114)

    def special_input(self, controller_input, length_in_seconds):
        if(ControllerInput.POWER_BUTTON == controller_input):
            if(length_in_seconds < 1):
                self.sleep()
            else:
                self.prompt_power_down()
        elif(ControllerInput.VOLUME_UP == controller_input):
            self.volume_up(5)
        elif(ControllerInput.VOLUME_DOWN == controller_input):
            self.volume_up(-5)

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
        # /mnt/SDCARD/Roms/, as on every other spruce device. This used to return
        # muOS's "/mnt/union/ROMS/", which is MuosDevice's path and does not exist
        # under spruce - nothing mounts /mnt/union here. Everything keyed off this
        # therefore looked in a directory that was not there: get_miyoo_games_file
        # found no miyoogamelist.xml, so every name fell back to the raw filename,
        # and the box art scraper and library searched the same empty path.
        return "/mnt/SDCARD/Roms/"
    
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
        return self.get_game_system_utils().get_save_state_image(rom_info)

    def get_wpa_supplicant_conf_path(self):
        return PyUiConfig.get_wpa_supplicant_conf_file_location("/mnt/SDCARD/Saves/spruce/wpa_supplicant.conf")

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

    def get_device_names(self):
        # Model name first so anything reading the first entry still gets the
        # specific device; the family token is what configs are written against.
        return [self.device_name, ANBERNIC_XX_FAMILY]

    def check_for_button_remap(self, input):
        return self.button_remapper.get_mappping(input)

    @throttle.limit_refresh(5)
    def get_wifi_connection_quality_info(self) -> WiFiConnectionQualityInfo:
        if(not self.is_wifi_enabled()):
            return WiFiConnectionQualityInfo(noise_level=0, signal_level=0, link_quality=0)

        # Signal comes from wpa_cli, not `iw`. BaseOS ships neither `iw` nor
        # /proc/net/wireless - the two sources every other device uses - so this
        # threw "[Errno 2] No such file or directory: 'iw'" on every poll and
        # returned zeroes, meaning the signal indicator has never worked on any
        # XX device. wpa_supplicant is already running and wpa_cli is already a
        # dependency of the scanner, so signal_poll costs nothing new. It reports:
        #     RSSI=-43
        #     LINKSPEED=434
        #     NOISE=9999
        #     FREQUENCY=5220
        # NOISE is 9999 when the driver does not report it, which is the case
        # here, so it is treated as unavailable rather than passed through.
        try:
            result = ProcessRunner.run(
                ["wpa_cli", "-i", "wlan0", "signal_poll"],
                timeout=3,
                print=False,
            )
            output = result.stdout or ""

            if result.returncode != 0 or "FAIL" in output:
                return WiFiConnectionQualityInfo(noise_level=0, signal_level=0, link_quality=0)

            signal_level = 0
            noise_level = 0
            have_signal = False
            for line in output.splitlines():
                line = line.strip()
                if line.startswith("RSSI="):
                    try:
                        signal_level = int(line.split("=", 1)[1])
                        have_signal = True
                    except ValueError:
                        pass
                elif line.startswith("NOISE="):
                    try:
                        noise = int(line.split("=", 1)[1])
                    except ValueError:
                        noise = 9999
                    # 9999 is wpa_supplicant's "not reported" sentinel.
                    if noise != 9999:
                        noise_level = noise

            # No usable RSSI means unknown, not excellent. Falling through with
            # signal_level still 0 would map to the top of the scale below, so a
            # reading we could not parse would show as a full-strength signal.
            if not have_signal:
                return WiFiConnectionQualityInfo(noise_level=0, signal_level=0, link_quality=0)

            # Same dBm -> 0..70 mapping the other devices use, so the status bar
            # thresholds behave identically across the fleet.
            if signal_level <= -100:
                link_quality = 0
            elif signal_level >= -50:
                link_quality = 70
            else:
                link_quality = int((signal_level + 100) * 1.4)

            return WiFiConnectionQualityInfo(
                noise_level=noise_level,
                signal_level=signal_level,
                link_quality=link_quality
            )

        except Exception as e:
            PyUiLogger.get_logger().error(f"An error occurred {e}")
            return WiFiConnectionQualityInfo(noise_level=0, signal_level=0, link_quality=0)

    @throttle.limit_refresh(10)
    def _get_ip_addr_text(self):
        import socket
        import fcntl
        import struct

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
        
    def get_ip_addr_text(self):
        if not self.is_wifi_enabled():
            return "Off"
        return self._get_ip_addr_text()
             
    def set_wifi_power(self, value):
        pass

    def stop_wifi_services(self):
        pass

    def start_wpa_supplicant(self):
        pass

    def start_udhcpc(self):
        # Overridden rather than inherited so this matches the invocation the
        # shell side uses in device_start_dhcp_client (device.sh) exactly - one
        # canonical form of the command on this device. -b matters: without it
        # udhcpc stays in the foreground as a child of MainUI, which spruce
        # kills and respawns around every game launch.
        try:
            # Match the whole invocation, not the bare name. udhcpc -b forks and
            # the process we spawned exits immediately, leaving a defunct entry
            # that ps renders as "[udhcpc]" until Python reaps it on its next
            # Popen. A bare substring test matches that corpse and skips
            # starting a real client - and it would do so in exactly the case
            # below where wpa_supplicant is already up, so no intervening Popen
            # has cleared it.
            if 'udhcpc -i wlan0' in self.get_running_processes().stdout:
                return

            subprocess.Popen([
                'udhcpc',
                '-i', 'wlan0',
                '-b',
                '-t', '5',
                '-T', '3'
            ])
            time.sleep(0.5)  # Wait for it to initialize
            PyUiLogger.get_logger().info("udhcpc started.")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error starting udhcpc: {e}")

    def start_wifi_services(self):
        pass

    def is_wifi_enabled(self):
        return self.system_config.is_wifi_enabled()

    def disable_wifi(self):
        self.system_config.set_wifi(0)
        self.system_config.save_config()
        self.stop_network_services()
        PyUiLogger.get_logger().info("Stopping WiFi Services")
        ProcessRunner.run(['killall', '-15', 'wpa_supplicant'])
        time.sleep(0.1)  
        ProcessRunner.run(['killall', '-9', 'wpa_supplicant'])
        time.sleep(0.1)  
        # udhcpc, not dhclient. There is no dhclient on this platform - not in
        # PATH, not anywhere on the filesystem - so these killalls matched
        # nothing and the real client survived every "WiFi off". Verified on a
        # CubeXX: udhcpc kept the same PID straight through an off/on cycle.
        ProcessRunner.run(['killall', '-15', 'udhcpc'])
        time.sleep(0.1)  
        ProcessRunner.run(['killall', '-9', 'udhcpc'])
        time.sleep(0.1)  
         
    def enable_wifi(self):
        self.system_config.set_wifi(1)
        self.system_config.save_config()
        # Before the "already running" return below, not after it - that path
        # still means WiFi is on, and the services still need starting.
        self.start_network_services()
        try:
            # Only the supplicant is skipped when it is already up - the DHCP
            # client is started unconditionally below. udhcpc exits on its own
            # when it gives up (-t 5 failed discovers), and it leaves
            # wpa_supplicant running when it does, so an early return here would
            # make "turn WiFi on" the one action that cannot recover an
            # interface that has associated but has no address.
            if 'wpa_supplicant' not in self.get_running_processes().stdout:
                # Also here, not just at startup: this is the call that actually
                # consumes the file, and it has to survive the config being
                # cleared or removed while the device is running - "Forget all
                # WiFi networks" rewrites it, and a user can delete it off the
                # card.
                self.ensure_wpa_supplicant_conf()

                # If not running, start it in the background
                subprocess.Popen([
                    'wpa_supplicant',
                    '-B',
                    '-D', 'nl80211',
                    '-i', 'wlan0',
                    '-c', self.get_wpa_supplicant_conf_path()
                ])
                time.sleep(0.5)  # Wait for it to initialize
                PyUiLogger.get_logger().info("wpa_supplicant started.")

            # Was subprocess.Popen(['dhclient', 'wlan0']), which raised
            # FileNotFoundError into the except below - so this logged "Error
            # starting wpa_supplicant" and started no DHCP client at all.
            self.start_udhcpc()

        except Exception as e:
            PyUiLogger.get_logger().error(f"Error starting wifi: {e}")

    def uses_deinit_v2(self):
        return True
