import json
import os

from utils.logger import PyUiLogger

class PyUiConfig:
    def __init__(self, initial_data=None):
        self._data = initial_data or {}

    def save(self):
        self._write_to_file("/mnt/SDCARD/App/PyUI/main-ui/config.json")
        self.load()

    def load(self):
        self._read_from_file("/mnt/SDCARD/App/PyUI/main-ui/config.json")

    def _write_to_file(self, filepath):
        try:
            os.makedirs(os.path.dirname(filepath), exist_ok=True)
            with open(filepath, 'w') as f:
                json.dump(self._data, f, indent=4)
            PyUiLogger.get_logger().info(f"Settings saved to {filepath}")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to write settings to {filepath}: {e}")

    def _read_from_file(self, filepath):
        try:
            with open(filepath, 'r') as f:
                self._data = json.load(f)
                PyUiLogger.get_logger().info(f"Settings loaded from {filepath}")
        except FileNotFoundError:
            PyUiLogger.get_logger().error(f"Settings file not found: {filepath}, using defaults.")
            self._data = {}
        except json.JSONDecodeError:
            PyUiLogger.get_logger().error(f"Invalid JSON in settings file: {filepath}, using defaults.")
            self._data = {}

    def __contains__(self, key):
        return key in self._data

    def get(self, key, default=None):
        return self._data.get(key, default)

    def set(self, key, value):
        self._data[key] = value

    def __getitem__(self, key):
        return self._data.get(key)

    def __setitem__(self, key, value):
        self._data[key] = value

    def to_dict(self):
        return self._data.copy()

    def clear(self):
        self._data.clear()

    def get_turbo_delay_ms(self):
        return self._data.get("turboDelayMs", 120)/1000

    def set_turbo_delay_ms(self, delay):
        self._data["turboDelayMs"] = delay