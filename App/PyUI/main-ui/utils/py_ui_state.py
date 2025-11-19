import json
import os

from utils.logger import PyUiLogger

class PyUiState:
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
    def clear(cls):
        cls._data = {}
        cls._write_to_file(cls._config_path)
        cls.load()

    @classmethod
    def _write_to_file(cls, filepath):
        try:
            os.makedirs(os.path.dirname(filepath), exist_ok=True)
            with open(filepath, 'w') as f:
                json.dump(cls._data, f, indent=4)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to write state to {filepath}: {e}")

    @classmethod
    def _read_from_file(cls, filepath):
        try:
            with open(filepath, 'r') as f:
                cls._data = json.load(f)
        except FileNotFoundError:
            PyUiLogger.get_logger().error(f"State file not found: {filepath}, using defaults.")
            cls._data = {}
        except json.JSONDecodeError as e:
            PyUiLogger.get_logger().error(
                f"Invalid JSON in state file: {filepath}, using defaults. Error: {e}"
            )
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
    def get_last_system_selection(cls):
        return cls.get("lastSystemSelection",None)

    @classmethod
    def set_last_system_selection(cls, value):
        cls._data["lastSystemSelection"] = value
        cls.save()

    @classmethod
    def get_last_app_selection(cls):
        return cls._data.get("lastAppSelection", None)

    @classmethod
    def set_last_app_selection(cls, app_label):
        cls._data["lastAppSelection"] = app_label
        cls.save()

    @classmethod
    def get_last_game_selection(cls, page_name):
        return cls._data.get(page_name, {}).get("lastGameSelection", None), cls._data.get(page_name, {}).get("subfolder", None)
        
    @classmethod
    def set_last_game_selection(cls, page_name, value, subfolder):
        if page_name not in cls._data:
            cls._data[page_name] = {}
        cls._data[page_name]["lastGameSelection"] = value
        cls._data[page_name]["subfolder"] = subfolder
        cls.save()

    @classmethod
    def get_in_game_selection_screen(cls):
        return cls.get("inGameSelectionScreen",False)

    @classmethod
    def set_in_game_selection_screen(cls, value):
        cls._data["inGameSelectionScreen"] = value
        cls.save()

    @classmethod
    def get_last_main_menu_selection(cls):
        return cls.get("lastMainMenuSelection",None)

    @classmethod
    def set_last_main_menu_selection(cls, value):
        cls._data["lastMainMenuSelection"] = value
        cls.save()

