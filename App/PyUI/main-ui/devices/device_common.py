

import os
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from audio.audio_player_none import AudioPlayerNone
from controller.controller_inputs import ControllerInput
from menus.language.language import Language
from devices.abstract_device import AbstractDevice
from devices.bluetooth.bluetooth_command import BluetoothCommand
from devices.miyoo.device_user_config import DeviceUserConfig
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_connection_quality_info import WiFiConnectionQualityInfo
from devices.wifi.wifi_scanner import WiFiNetwork, WiFiScanner
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
                elif(Controller.last_input() == ControllerInput.X and self.reboot_cmd() is not None):
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

    # Screensaver backlight. The panel is the largest single load on a handheld
    # (measured on the Flip: ~400 mW between backlight level 1 and 10), and a
    # screensaver drawing a dark frame at full backlight saves nothing. Level 1
    # keeps the screen faintly visible so a lit device still reads as "on".
    #
    # Dimming changes only the in-memory level; the user's level is remembered
    # here and written back on restore. Written back, not just re-read: the
    # shell brightness hotkeys (buttons_watchdog) derive the level from the raw
    # backlight value, so a key pressed while dimmed would save a level computed
    # from the dimmed value. Restore wins over that.
    SCREENSAVER_BACKLIGHT_LEVEL = 1
    _screensaver_saved_backlight = None

    def dim_backlight_for_screensaver(self):
        if not hasattr(self, "_set_lumination_to_config"):
            return False
        self.system_config.reload_config()
        level = self.system_config.backlight
        if level <= self.SCREENSAVER_BACKLIGHT_LEVEL:
            return False
        self._screensaver_saved_backlight = level
        self.system_config.set_backlight(self.SCREENSAVER_BACKLIGHT_LEVEL)
        self._set_lumination_to_config()
        return True

    def restore_backlight_after_screensaver(self):
        saved = self._screensaver_saved_backlight
        self._screensaver_saved_backlight = None
        # Fresh copy first so a volume change made meanwhile is not clobbered.
        self.system_config.reload_config()
        if saved is not None:
            self.system_config.set_backlight(saved)
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
            
    # ---- Bluetooth --------------------------------------------------------
    # As with WiFi: the shell owns the radio and its daemons, PyUI saves the
    # on/off setting and calls bluetoothCmd for the rest. See
    # App/PyUI/bluetooth_readme.txt for the command contract.

    def _bluetooth_cmd(self, *args, timeout=20):
        cmd = PyUiConfig.get_bluetooth_cmd()
        if not cmd or not os.path.exists(cmd):
            return None
        try:
            result = subprocess.run([cmd, *args], capture_output=True, text=True,
                                    stdin=subprocess.DEVNULL, timeout=timeout)
            if result.returncode != 0:
                PyUiLogger.get_logger().error(f"bluetooth {args[0]} exited {result.returncode}")
                return None
            return result.stdout
        except Exception as e:
            PyUiLogger.get_logger().error(f"bluetooth {args[0]} failed: {e}")
            return None

    def is_bluetooth_enabled(self):
        return self.system_config.is_bluetooth_enabled()

    def enable_bluetooth(self):
        self.system_config.set_bluetooth(1)
        self._apply_bluetooth()

    def disable_bluetooth(self):
        self.system_config.set_bluetooth(0)
        self._apply_bluetooth()

    # apply brings the radio up or down, which takes seconds; keep it off the
    # UI thread. A toggle made while one is running gets one more apply, which
    # reads the saved setting, so the last toggle wins.
    _bt_apply_lock = threading.Lock()
    _bt_apply_running = False
    _bt_apply_again = False
    _bt_last_connected = None

    def _apply_bluetooth(self):
        with self._bt_apply_lock:
            if self._bt_apply_running:
                self._bt_apply_again = True
                return
            self._bt_apply_running = True
        threading.Thread(target=self._bluetooth_apply_worker, daemon=True).start()

    def _bluetooth_apply_worker(self):
        while True:
            self._bluetooth_cmd("apply", timeout=30)
            self._bluetooth_status.force_refresh()
            self.refresh_audio_route()
            with self._bt_apply_lock:
                if not self._bt_apply_again:
                    self._bt_apply_running = False
                    return
                self._bt_apply_again = False

    @throttle.limit_refresh(10, background=True)
    def _bluetooth_status(self):
        out = self._bluetooth_cmd("status", timeout=15) or ""
        return dict(line.split("=", 1) for line in out.splitlines() if "=" in line)

    def get_bluetooth_status(self):
        """For the top bar: None unless something is connected, then "audio" or
        "gamepad" when only that kind is, otherwise "on"."""
        if not self.is_bluetooth_enabled():
            return None
        status = self._bluetooth_status()
        if status.get("radio") != "1":
            return None
        # Headsets also connect and drop on their own (boot reconnect, power off).
        if status.get("connected") != self._bt_last_connected:
            self._bt_last_connected = status.get("connected")
            self.refresh_audio_route()
        icons = [i for i in status.get("connected_icon", "").split(",") if i]
        if not icons:
            return None
        if all(i.startswith("audio") for i in icons):
            return "audio"
        if all(i == "input-gaming" for i in icons):
            return "gamepad"
        return "on"

    def get_bluetooth_scanner(self):
        if not hasattr(self, "_bluetooth_scanner"):
            status = (self._bluetooth_cmd("status") or "").splitlines()
            self._bluetooth_scanner = BluetoothCommand(self._bluetooth_cmd) if "radio=1" in status else None
        return self._bluetooth_scanner

    # ---- WiFi -------------------------------------------------------------
    # The shell owns the radio and reports on it; PyUI only saves the on/off
    # setting and shows what `wifiCmd status` says. See App/PyUI/wifi_readme.txt
    # for the command contract. With no wifiCmd configured, the reads fall back
    # to the interface and /proc so hosts without spruce's script still work.

    def _wifi_cmd(self, *args, stdin_text=None, timeout=10):
        """Run the configured WiFi command. Returns stdout, or None when there
        is no command or it failed."""
        cmd = PyUiConfig.get_wifi_cmd()
        if not cmd or not os.path.exists(cmd):
            return None
        try:
            run_args = dict(capture_output=True, text=True, timeout=timeout)
            if stdin_text is None:
                run_args["stdin"] = subprocess.DEVNULL
            else:
                run_args["input"] = stdin_text
            result = subprocess.run([cmd, *args], **run_args)
            if result.returncode != 0:
                PyUiLogger.get_logger().error(f"wifi {args[0]} exited {result.returncode}")
                return None
            return result.stdout
        except Exception as e:
            PyUiLogger.get_logger().error(f"wifi {args[0]} failed: {e}")
            return None

    # background: the top bar asks for this every frame, and `wifiCmd status` takes
    # ~0.2 s on an A133P. Read on the UI thread, that stalled one frame per refresh
    # (every second while a change settles), and Controller.get_input drops a key
    # pressed during a frame longer than 0.2 s: typing a WiFi password lost keys.
    @throttle.limit_refresh(10, fast_seconds=1, fast_while="_wifi_settle_until", background=True)
    def _wifi_status(self):
        """`wifiCmd status` as a dict of its key=value lines."""
        out = self._wifi_cmd("status", timeout=15)
        if out is None:
            return self._wifi_status_fallback()
        status = {}
        for line in out.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                status[key.strip()] = value.strip()
        return status

    def _wifi_status_fallback(self):
        """No WiFi command on this host: read the interface directly."""
        status = {"radio": "1", "saved": "1"}
        if not self.is_wifi_enabled():
            status["link"] = "off"
            return status
        ip = ""
        try:
            result = subprocess.run(["ip", "-4", "addr", "show", "wlan0"], capture_output=True, text=True, timeout=5)
            for line in result.stdout.splitlines():
                line = line.strip()
                if line.startswith("inet "):
                    ip = line.split()[1].split("/")[0]
                    break
        except Exception:
            status["link"] = "error"
            return status
        if not ip:
            status["link"] = "connecting"
            return status
        status["link"] = "connected"
        status["ip"] = ip
        try:
            with open("/proc/net/wireless") as f:
                for line in f:
                    parts = line.split()
                    if parts and parts[0] == "wlan0:":
                        status["signal"] = str(int(float(parts[3].rstrip("."))))
        except Exception:
            pass
        return status

    def _wifi_signal_dbm(self):
        try:
            return int(self._wifi_status().get("signal", ""))
        except ValueError:
            return None

    def get_wifi_status(self):
        if not self.is_wifi_enabled():
            return WifiStatus.OFF
        if self._wifi_status().get("link") != "connected":
            return WifiStatus.OFF

        rssi = self._wifi_signal_dbm()
        if rssi is None:
            # Joined with an address but no strength reading: usable, unknown.
            return WifiStatus.OKAY
        if rssi >= -50:
            return WifiStatus.GREAT
        elif rssi >= -67:
            return WifiStatus.GOOD
        elif rssi >= -75:
            return WifiStatus.OKAY
        else:
            return WifiStatus.BAD

    def get_wifi_connection_quality_info(self) -> WiFiConnectionQualityInfo:
        rssi = self._wifi_signal_dbm()
        if rssi is None or self._wifi_status().get("link") != "connected":
            return WiFiConnectionQualityInfo(noise_level=0, signal_level=-200, link_quality=0)
        if rssi <= -100:
            link_quality = 0
        elif rssi >= -50:
            link_quality = 70
        else:
            link_quality = int((rssi + 100) * 1.4)
        return WiFiConnectionQualityInfo(noise_level=0, signal_level=rssi, link_quality=link_quality)

    def get_running_processes(self):
        #bypass ProcessRunner.run_and_print() as it makes the log too big
        return subprocess.run(['ps', '-f'], capture_output=True, text=True)



    # Saved networks live on the card, not on the handheld, so a password
    # entered on one device is enough for every device the card is moved to.
    # This is the path the shell has always used - see WPA_SUPPLICANT_FILE in
    # helperFunctions.sh - and PyUI used to disagree with it, writing to
    # internal flash while the device booted its supplicant from the card.
    #
    # Saves/spruce is untracked, so an update never extracts a default over it.
    # Hosts that manage WiFi another way override this and return None.
    WPA_SUPPLICANT_CONF = "/mnt/SDCARD/Saves/spruce/wpa_supplicant.conf"

    def get_wpa_supplicant_conf_path(self):
        return PyUiConfig.get_wpa_supplicant_conf_file_location(
            DeviceCommon.WPA_SUPPLICANT_CONF
        )

    def _run_wifi_script(self, *args, stdin_text=None):
        # Radio changes return at once: the command does the work in a
        # detached copy of itself. Output is not needed.
        self._wifi_cmd(*args, stdin_text=stdin_text)

    def _save_wifi_setting(self, value):
        self.system_config.reload_config()
        self.system_config.set_wifi(value)
        self.system_config.save_config()

    def enable_wifi(self):
        self._save_wifi_setting(1)
        self._run_wifi_script("apply")

    def disable_wifi(self):
        self._save_wifi_setting(0)
        self._run_wifi_script("apply")

    def wifi_connect(self, ssid: str, password):
        """Apply a network selection. password is None for an open network.

        The network goes to the WiFi command on stdin, never on a command line.
        """
        self._run_wifi_script("connect", stdin_text=f"{ssid}\n{password or ''}\n")

    # Deadline (time.time()) until which the WiFi status cache refreshes every
    # second instead of every 10 s; see utils/throttle.limit_refresh.
    _wifi_settle_until = 0.0

    def note_wifi_change(self, settle_seconds=60):
        """The user just toggled WiFi or picked a network: drop the throttled
        status cache now and keep it fast while the join settles, so the
        Settings row and the top-bar icon follow the link within a second."""
        self._wifi_settle_until = time.time() + settle_seconds
        for cls in type(self).__mro__:
            fn = cls.__dict__.get("_wifi_status")
            force = getattr(fn, "force_refresh", None)
            if force:
                force()

    def wifi_has_saved_network(self):
        """True when at least one network is saved. Unknown answers True: never
        claim "no network" on a guess."""
        saved = self._wifi_status().get("saved")
        if saved is None:
            return True
        try:
            return int(saved) > 0
        except ValueError:
            return True

    def get_wifi_saved_networks(self):
        """Saved network names, in the order the WiFi command lists them."""
        out = self._wifi_cmd("saved")
        if out is None:
            return []
        return [line for line in out.splitlines() if line]

    def wifi_scan(self):
        """One `wifiCmd scan`: the networks visible right now. Blocks for a few
        seconds, so WiFiScanner calls it from its worker thread."""
        out = self._wifi_cmd("scan", timeout=30)
        networks = []
        if out is None:
            return networks
        for line in out.splitlines():
            parts = line.split("\t")
            if len(parts) < 5:
                continue
            ssid, signal, freq, secured, bssid = parts[:5]
            try:
                networks.append(WiFiNetwork(
                    bssid=bssid,
                    frequency=int(freq),
                    signal_level=int(signal),
                    flags="WPA" if secured == "1" else "",
                    ssid=ssid,
                ))
            except ValueError:
                continue
        return networks

    def wifi_connected_network(self):
        """(ssid, frequency MHz) of the joined network, or (None, None)."""
        status = self._wifi_status()
        ssid = status.get("ssid") or None
        try:
            freq = int(status.get("freq", ""))
        except ValueError:
            freq = None
        return ssid, freq

    def wifi_pending_text(self):
        """Status for a radio that is on but has no address.

        "Connecting" used to cover two very different states: joining a saved
        network, and having no network to join at all (a fresh card, a cleared
        conf). The second is the one people can act on - open the network list -
        so say so instead of implying a join that will never finish.
        """
        if not self.wifi_has_saved_network():
            return Language.label("wifiStatusNoNetwork", "No network selected")
        return Language.label("wifiStatusConnecting", "Connecting")

    def get_ip_addr_text(self):
        if not self.is_wifi_enabled():
            return Language.label("wifiStatusOff", "Off")
        status = self._wifi_status()
        link = status.get("link", "")
        if link == "connected":
            return status.get("ip") or Language.label("wifiStatusConnecting", "Connecting")
        if link == "no_radio":
            return Language.label("wifiStatusUnsupported", "Unsupported")
        if link == "off":
            return Language.label("wifiStatusOff", "Off")
        if link == "error":
            return Language.label("wifiStatusError", "Error")
        if link == "no_network":
            return Language.label("wifiStatusNoNetwork", "No network selected")
        if link == "connecting":
            return Language.label("wifiStatusConnecting", "Connecting")
        return self.wifi_pending_text()

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
    
    def get_zoneinfo_dir(self):
        return PyUiConfig.get_timezone_dir()

    def supports_timezone_setting(self):
        return os.path.isdir(self.get_zoneinfo_dir())

    def supports_automatic_timezone(self):
        """
        Whether timeFunctions.sh may pick the zone from the network location
        and this class will apply it from the shared config. False on a device
        whose timezone lives in its own system layer (the Pixel 2).
        """
        return self.supports_timezone_setting() and self.supports_wifi()

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
        self._applied_timezone = timezone
        PyUiLogger.get_logger().info(f"Applied timezone {timezone} from {zone_file}")
        return True

    def _watch_shared_timezone(self):
        """
        timeFunctions.sh writes an automatically detected zone into the
        shared config once the network is up, from outside this process. TZ
        lives only in our environment, so watch the file and re-apply. Cheap:
        one stat every few seconds. The file is created empty first so the
        watcher has something to stat; an empty file still means "no zone".
        """
        try:
            from devices.utils.file_watcher import FileWatcher
            system_config = self.get_system_config()
            path = getattr(system_config, "SHARED_CONFIG_PATH", None)
            if not path:
                return
            if not os.path.isfile(path):
                system_config._write_shared(system_config._read_shared())
            FileWatcher().start_file_watcher(path, self._on_shared_timezone_changed, interval=3.0)
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Could not watch shared config for timezone changes: {e}")

    def _on_shared_timezone_changed(self):
        try:
            system_config = self.get_system_config()
            if not getattr(system_config, "has_timezone", lambda: False)():
                return
            timezone = system_config.get_timezone()
            if timezone and timezone != getattr(self, "_applied_timezone", None):
                DeviceCommon.apply_timezone(self, timezone)
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Could not re-apply timezone: {e}")

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

        if self.supports_automatic_timezone():
            self._watch_shared_timezone()

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

    def refresh_audio_route(self):
        # Called when a Bluetooth audio device connects or Bluetooth is turned
        # off, for devices that can move their output to it. Default: nothing.
        pass

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

    def _apply_cpu_mode(self, mode):
        cpu_script = PyUiConfig.get_cpu_mode_cmd()
        if not os.path.exists(cpu_script):
            return

        try:
            subprocess.run(
                [cpu_script, mode],
                check=False,
                timeout=10
            )
        except Exception as e:
            PyUiLogger.get_logger().warning(
                f"Could not apply CPU mode {mode}: {e}"
            )

    def set_cpu_low_power(self):
        self._apply_cpu_mode("powersave")

    def set_cpu_normal(self):
        self._apply_cpu_mode("smart")

    def animation_divisor(self):
        return self.get_system_config().animation_speed(1)

    def get_wifi_menu(self):
        return WifiMenu()

    def get_new_wifi_scanner(self):
        return WiFiScanner(self.wifi_scan, self.wifi_connected_network)

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

    def get_emulator_arch(self, menu_options: dict, rom_file_path=None):
        """The Emulator_64/Emulator_32 key matching the RA build, or None if this device lacks that key."""
        ra_build = menu_options.get("raBuild")
        if not ra_build:
            return None
        if not any(name in (ra_build.get("devices") or []) for name in self.get_device_names()):
            return None

        selected = ra_build.get("selected")
        if rom_file_path is not None:
            selected = (ra_build.get("overrides") or {}).get(rom_file_path, selected)

        def claims(key):
            option = menu_options.get(key)
            if not option:
                return False
            return any(name in (option.get("devices") or []) for name in self.get_device_names())

        if selected == "32-bit" and claims("Emulator_32"):
            return "Emulator_32"
        if selected == "64-bit" and claims("Emulator_64"):
            return "Emulator_64"
        return None

    def get_selected_emulator(self, menu_options: dict):
        arch_key = self.get_emulator_arch(menu_options)
        for key, option in menu_options.items():
            if key.startswith("Emulator") and (arch_key is None or key == arch_key):
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
