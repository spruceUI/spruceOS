
from dataclasses import dataclass
import json
import os
from typing import List
from apps.app_config import AppConfig
from devices.device import Device
from menus.games.utils.rom_info import RomInfo
from utils.logger import PyUiLogger

@dataclass
class AppEntry:
    launch: str
    hidden: bool

    def __init__(self, app_config: AppConfig, hidden: bool = False):
        self.launch = app_config.get_launch()
        self.hidden = hidden

class AppListManager():
    def __init__(self, entries_file):
        self.entries_file = entries_file
        self._entries: List[AppEntry] = []
        self.load_from_file()

    def _add_app(self, app_config: AppConfig):
        new_entry = AppEntry(app_config)
        if not (any(existing.launch == new_entry.launch for existing in self._entries)):
            self._entries.insert(0, new_entry)

        self.save_to_file()

    def save_to_file(self):
        try:
            with open(self.entries_file, 'w') as f:
                json.dump(
                    [f.__dict__ for f in self._entries],
                    f,
                    indent=4
                )
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to save entries: {e}")

    def load_from_file(self):
        try:
            # Check if file exists, if not, create it with an empty JSON array
            if not os.path.exists(self.entries_file):
                with open(self.entries_file, 'w') as f:
                    json.dump([], f)

            # Load data from the file
            with open(self.entries_file, 'r') as f:
                data = json.load(f)
                self._entries = [AppEntry(**entry) for entry in data]
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to load entries: {e}")
            
    def get_apps(self) -> List[AppEntry]:
        return self._entries

    def get_app(self, app_config: AppConfig):
        self._add_app(app_config)
        return next((e for e in self._entries if e.launch == app_config.get_launch()), None)
    