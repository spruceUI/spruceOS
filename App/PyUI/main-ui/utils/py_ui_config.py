import json
import os

from utils.logger import PyUiLogger
import time

class PyUiConfig:
    _data = {}
    _config_path = None

    @classmethod
    def init(cls, config_path, initial_data=None):
        cls._config_path = config_path
        cls._data = initial_data or {}
        cls.load()

        os.environ['TZ'] = cls.get("timezone",'America/New_York')
        time.tzset()  

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
                PyUiLogger.get_logger().info(f"Settings loaded from {filepath}")
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
    def get_main_menu_title(cls):
        return cls._data.get("mainMenuTitle", "PyUI")

    @classmethod
    def get_timezone(cls):
        return cls.get("timezone",'America/New_York')
   
    @classmethod
    def set_timezone(cls, tz):
        cls._data["timezone"] = tz
        os.environ['TZ'] = tz
        time.tzset()  
        cls.save()

    @classmethod
    def show_clock(cls):
        return cls.get("showClock",True)

    @classmethod
    def set_show_clock(cls, value):
        cls._data["showClock"] = value
        cls.save()

    @classmethod
    def use_24_hour_clock(cls):
        return cls.get("use24HourClock",False)

    @classmethod
    def set_use_24_hour_clock(cls, value):
        cls._data["use24HourClock"] = value
        cls.save()

    @classmethod
    def show_am_pm(cls):
        return cls.get("showAmPm",True)

    @classmethod
    def set_show_am_pm(cls, value):
        cls._data["showAmPm"] = value
        cls.save()

    @classmethod
    def animations_enabled(cls):
        return cls.get("animationsEnabled",True)
