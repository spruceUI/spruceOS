
import json
import os
import sys

from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig


class Language:
    _data = {}
    _config_path = None
    @classmethod

    def init(cls):
        cls._data = {}
        cls.load()

    @classmethod
    def load(cls):
        language = PyUiConfig.get_language()
        if(language is not None):
            PyUiLogger.get_logger().info(f"language is {language}")
            base_dir = os.path.abspath(sys.path[0])
            parent_dir = os.path.dirname(base_dir)
            lang_dir = os.path.join(parent_dir, "lang")
            cls._config_path = os.path.join(lang_dir, language+".json")
        else:
            cls._config_path = None
        cls._read_from_file(cls._config_path)

    @classmethod
    def _read_from_file(cls, filepath):
        if(filepath is not None):
            try:
                with open(filepath, 'r') as f:
                    cls._data = json.load(f)
                    PyUiLogger.get_logger().info(f"Languages loaded from {filepath}")
            except FileNotFoundError:
                PyUiLogger.get_logger().error(f"Languages file not found: {filepath}, using defaults.")
                cls._data = {}
            except json.JSONDecodeError:
                PyUiLogger.get_logger().error(f"Invalid JSON in languages file: {filepath}, using defaults.")
                cls._data = {}
        else:
            PyUiLogger.get_logger().error(f"Languages file not found: {filepath}, using defaults.")
            cls._data = {}

    @classmethod
    def save(cls):
        cls._write_to_file(cls._config_path)
        cls.load()

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
    def games(cls):
        return cls._data.get("Games","Games")

    @classmethod
    def recents(cls):
        return cls._data.get("Recents","Recents")

    @classmethod
    def apps(cls):
        return cls._data.get("Apps","Apps")

    @classmethod
    def collections(cls):
        return cls._data.get("Collections","Collections")

    @classmethod
    def favorites(cls):
        return cls._data.get("Favorites","Favorites")

    @classmethod
    def settings(cls):
        return cls._data.get("Settings","Settings")
