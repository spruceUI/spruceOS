import json
import os
from pathlib import Path

from utils.logger import PyUiLogger

class PyUiConfig:
    _data = {}
    _config_path = None
    _current_dir = None

    @classmethod
    def init(cls, config_path, initial_data=None):
        cls._config_path = config_path
        cls._data = initial_data or {}
        cls.load()
        cls._current_dir = Path(__file__).resolve().parent

    @classmethod
    def save(cls):
        cls._write_to_file(cls._config_path)
        cls.load()

    @classmethod
    def load(cls):
        cls._read_from_file(cls._config_path)

    @classmethod
    def _write_to_file(cls, filepath):
        try:
            os.makedirs(os.path.dirname(filepath), exist_ok=True)
            # Stage beside the target and rename: a truncating in-place write
            # loses the whole config if power is cut mid-write, and this file
            # is rewritten on every settings change.
            tmp_path = f"{filepath}.tmp"
            with open(tmp_path, 'w') as f:
                json.dump(cls._data, f, indent=4)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_path, filepath)
            PyUiLogger.get_logger().info(f"Settings saved to {filepath}")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to write settings to {filepath}: {e}")

    @classmethod
    def _read_from_file(cls, filepath):
        try:
            with open(filepath, 'r') as f:
                cls._data = json.load(f)
                #PyUiLogger.get_logger().info(f"Settings loaded from {filepath}")
        except FileNotFoundError:
            PyUiLogger.get_logger().error(f"Settings file not found: {filepath}, using defaults.")
            cls._data = {}
        except json.JSONDecodeError:
            PyUiLogger.get_logger().error(f"Invalid JSON in settings file: {filepath}, using defaults.")
            cls._data = {}

    @classmethod
    def __contains__(cls, key):
        return key in cls._data

    @classmethod
    def get(cls, key, default=None):
        return cls._data.get(key, default)

    @classmethod
    def set(cls, key, value):
        cls._data[key] = value

    @classmethod
    def __getitem__(cls, key):
        return cls._data.get(key)

    @classmethod
    def __setitem__(cls, key, value):
        cls._data[key] = value

    @classmethod
    def to_dict(cls):
        return cls._data.copy()

    @classmethod
    def clear(cls):
        cls._data.clear()

    @classmethod
    def get_turbo_delay_ms(cls):
        return cls._data.get("turboDelayMs", 120) / 1000

    @classmethod
    def set_turbo_delay_ms(cls, delay):
        cls._data["turboDelayMs"] = delay

    @classmethod
    def enable_button_watchers(cls):
        return cls._data.get("enableButtonWatchers", True)

    @classmethod
    def get_fallback_font(cls):
        return cls._data.get("fallbackFontPath", cls._current_dir / "promptfont.ttf")

    @classmethod
    def get_main_menu_title(cls):
        return cls._data.get("mainMenuTitle", "PyUI")

    @classmethod
    def get_cfw_name(cls):
        return cls._data.get("mainMenuTitle", "CFW")

    @classmethod
    def use_24_hour_clock(cls):
        return cls.get("use24HourClock",False)

    @classmethod
    def set_use_24_hour_clock(cls, value):
        cls._data["use24HourClock"] = value
        cls.save()

    @classmethod
    def show_all_game_systems(cls):
        return cls.get("showAllGameSystems",False)

    @classmethod
    def set_show_all_game_systems(cls, value):
        cls._data["showAllGameSystems"] = value
        cls.save()

    @classmethod
    def sync_time_via_network(cls):
        # On by default: these handhelds have no battery-backed RTC, so without
        # this a cold boot sits years in the past and every HTTPS request fails
        # with "certificate is not yet valid". Off is a real choice though -
        # some games read the clock, so a user may want it held where they set it.
        return cls.get("syncTimeViaNetwork",True)

    @classmethod
    def set_sync_time_via_network(cls, value):
        cls._data["syncTimeViaNetwork"] = value
        cls.save()

    @classmethod
    def show_am_pm(cls):
        return cls.get("showAmPm",True)

    @classmethod
    def set_show_am_pm(cls, value):
        cls._data["showAmPm"] = value
        cls.save()

    @classmethod
    def game_system_sort_mode(cls):
        return cls.get("gameSystemSortMode","Alphabetical")

    @classmethod
    def set_game_system_sort_mode(cls, value):
        cls._data["gameSystemSortMode"] = value
        cls.save()

    @classmethod
    def game_system_sort_type_priority(cls):
        return cls.get("gameSystemSortTypePrio",1)

    @classmethod
    def set_game_system_sort_type_priority(cls, value):
        cls._data["gameSystemSortTypePrio"] = value
        cls.save()

    @classmethod
    def game_system_sort_brand_priority(cls):
        return cls.get("gameSystemSortBrandPrio",2)

    @classmethod
    def set_game_system_sort_brand_priority(cls, value):
        cls._data["gameSystemSortBrandPrio"] = value
        cls.save()

    @classmethod
    def game_system_sort_year_priority(cls):
        return cls.get("gameSystemSortYearPrio",3)
    
    @classmethod
    def set_game_system_sort_year_priority(cls, value):
        cls._data["gameSystemSortYearPrio"] = value
        cls.save()

    @classmethod
    def game_system_sort_name_priority(cls):
        return cls.get("gameSystemSortNamePrio",4)
    
    @classmethod
    def set_game_system_sort_name_priority(cls, value):
        cls._data["gameSystemSortNamePrio"] = value
        cls.save()

    # The language belongs to whoever owns the card, and this file is replaced
    # on a full update, so when "sharedSystemConfig" names the card-wide file
    # (where the timezone lives too) the language is kept there. Shell scripts
    # read it from that file to follow the UI language.
    LANGUAGE_KEY = "language"

    @classmethod
    def _read_shared_config(cls):
        path = cls.get("sharedSystemConfig")
        if not path:
            return None
        try:
            with open(path) as f:
                data = json.load(f)
            return data if isinstance(data, dict) else {}
        except (OSError, json.JSONDecodeError):
            return {}

    @classmethod
    def get_language(cls):
        shared = cls._read_shared_config()
        if shared and shared.get(cls.LANGUAGE_KEY):
            return shared[cls.LANGUAGE_KEY]
        language = cls.get(cls.LANGUAGE_KEY)
        if shared is not None and language:
            # Chosen before the language moved card-wide: adopt it.
            cls._write_shared_language(shared, language)
        return language or "English"

    @classmethod
    def set_language(cls, language):
        cls._data[cls.LANGUAGE_KEY] = language
        cls.save()
        shared = cls._read_shared_config()
        if shared is not None:
            cls._write_shared_language(shared, language)

    @classmethod
    def _write_shared_language(cls, shared, language):
        shared[cls.LANGUAGE_KEY] = language
        path = cls.get("sharedSystemConfig")
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            tmp_path = f"{path}.tmp"
            with open(tmp_path, 'w') as f:
                json.dump(shared, f, indent=4)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_path, path)
        except OSError as e:
            PyUiLogger.get_logger().error(f"Could not write {path}: {e}")

    @classmethod
    def include_stock_os_launch_option(cls):
        return cls.get("includeStockOsLaunchOption",True)

    @classmethod
    def allow_pyui_game_switcher(cls):
        return cls.get("allowPyUiGameSwitcher",True)

    @classmethod
    def get_gameswitcher_path(cls):
        return cls.get("gameSwitcherPath",None)

    @classmethod
    def cfw_tasks_json(cls):
        return cls.get("cfwTasks",None)

    @classmethod
    def get_wpa_supplicant_conf_file_location(cls, default_path):
        return cls.get("wpaSupplicantConfigFileLocation",default_path)

    @classmethod
    def get_activity_log_path(cls):
        return cls.get("activityLogPath",None)

    @classmethod
    def get_cheevos_remove_cmd(cls):
        return cls.get("cheevosRemoveCmd",None)

    @classmethod
    def get_raproxy_cli_cmd(cls):
        return cls.get("raproxyCliCmd",None)
    
    @classmethod
    def get_about_entries(cls):
        return cls.get("aboutEntries",[])
    
    @classmethod
    def get_poweroff_cmd(cls):
        return cls.get("poweroffCmd",None)
    
    @classmethod
    def get_shutdown_image(cls):
        return cls.get("shutdownImage",None)

    @classmethod
    def get_reboot_cmd(cls):
        return cls.get("rebootCmd",None)

    @classmethod
    def get_long_task_cmd(cls):
        return cls.get("longTaskCmd",None)

    @classmethod
    def mimic_miyoo_mainui_mode(cls):
        return cls.get("mimicMiyooMainUiMode",False)

    @classmethod
    def ignore_menu_button_combination_presses(cls):
        return cls.get("ignoreMenuCombinationPresses",False)

    @classmethod
    def get_timezone_dir(cls):
        return cls.get("timezoneDir","")

    @classmethod
    def get_cpu_mode_cmd(cls):
        return cls.get("cpuModeCmd",None)

    @classmethod
    def get_backlight_cmd(cls):
        return cls.get("backlightCmd",None)

    @classmethod
    def get_volume_cmd(cls):
        return cls.get("volumeCmd",None)

    @classmethod
    def get_bt_audio_device_cmd(cls):
        return cls.get("btAudioDeviceCmd",None)

    @classmethod
    def get_usb_audio_supported_cmd(cls):
        return cls.get("usbAudioSupportedCmd",None)

    @classmethod
    def get_usb_audio_route_path(cls):
        return cls.get("usbAudioRoutePath",None)

    @classmethod
    def get_wifi_cmd(cls):
        return cls.get("wifiCmd",None)

    @classmethod
    def get_bluetooth_cmd(cls):
        return cls.get("bluetoothCmd",None)

    @classmethod
    def get_cache_cheevos_cmd(cls):
        return cls.get("cacheCheevosCmd",None)

    @classmethod
    def get_cfw_version_file(cls):
        return cls.get("cfwVersionFile","0.0.0")