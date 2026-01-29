import json
import os

from utils.logger import PyUiLogger

class PyUiConfig:
    _data = {}
    _config_path = None

    @classmethod
    def init(cls, config_path, initial_data=None):
        cls._config_path = config_path
        cls._data = initial_data or {}
        cls.load()

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
            with open(filepath, 'w') as f:
                json.dump(cls._data, f, indent=4)
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
    def enable_wifi_monitor(cls):
        return cls._data.get("enableWifiMonitor", True)

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

    @classmethod
    def get_language(cls):
        return cls.get("language","English")

    @classmethod
    def set_language(cls, language):
        cls._data["language"] = language
        cls.save()

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