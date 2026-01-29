from dataclasses import dataclass
import json
import os
from typing import List
from apps.app_config import AppConfig
from utils.logger import PyUiLogger

@dataclass
class AppEntry:
    launch: str
    hidden: bool = False

    def __init__(self, launch: str, hidden: bool = False):
        self.launch = launch
        self.hidden = hidden

class AppListManager:
    def __init__(self, entries_file: str):
        self.entries_file = entries_file
        self._entries: List[AppEntry] = []
        self._entries_dict: dict[str, AppEntry] = {}
        self.load_from_file()

    def ensure_app_exists(self, app_config: AppConfig):
        """Add the app if it doesn't exist, and save to disk."""
        launch = app_config.get_launch()
        if launch not in self._entries_dict:
            new_entry = AppEntry(launch)
            self._entries.insert(0, new_entry)  # keep list for order
            self._entries_dict[launch] = new_entry
            self.save_to_file()

    def save_to_file(self):
        try:
            with open(self.entries_file, 'w') as outfile:
                json.dump(
                    [entry.__dict__ for entry in self._entries],
                    outfile,
                    indent=4
                )
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to save entries: {e}")

    def load_from_file(self):
        try:
            # Create file if missing
            if not os.path.exists(self.entries_file):
                with open(self.entries_file, 'w') as f:
                    json.dump([], f)

            # Load entries
            with open(self.entries_file, 'r') as f:
                data = json.load(f)
                self._entries = [AppEntry(**entry) for entry in data]
                # Build dict for O(1) lookups
                self._entries_dict = {entry.launch: entry for entry in self._entries}

        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to load entries: {e}")

    def get_apps(self) -> List[AppEntry]:
        return self._entries

    def get_app(self, app_config: AppConfig) -> AppEntry:
        """Return the AppEntry for the given AppConfig, creating and saving it if missing."""
        launch = app_config.get_launch()
        entry = self._entries_dict.get(launch)

        if entry is None:
            entry = AppEntry(launch)
            self._entries.insert(0, entry)
            self._entries_dict[launch] = entry
            self.save_to_file()

        return entry
