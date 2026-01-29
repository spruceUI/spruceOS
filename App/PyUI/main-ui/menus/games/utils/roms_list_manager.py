from dataclasses import dataclass
import json
import os
from pathlib import Path
from typing import List, Tuple
from devices.device import Device
from menus.games.utils.rom_info import RomInfo
from utils.logger import PyUiLogger

@dataclass
class RomsListEntry:
    rom_file_path: str
    game_system_name: str
    display_name: str = None

    def __init__(self, rom_file_path, game_system_name, display_name=None):
        self.rom_file_path = rom_file_path
        self.game_system_name = game_system_name
        self.display_name = display_name

class RomsListManager:
    def __init__(self, entries_file):
        self.entries_file = entries_file
        self._entries: List[RomsListEntry] = []
        self._entries_dict: dict[Tuple[str, str], RomsListEntry] = {}
        self.load_from_file()
        self.game_system_utils = Device.get_device().get_game_system_utils()
        self.rom_info_list = self.load_entries_as_rom_info()

    def _entry_key(self, rom_file_path: str, game_system_name: str) -> Tuple[str, str]:
        return (str(Path(rom_file_path).resolve()), game_system_name)

    def add_game(self, rom_info: RomInfo):
        key = self._entry_key(rom_info.rom_file_path, rom_info.game_system.folder_name)

        if key in self._entries_dict:
            self.remove_game(rom_info)

        new_entry = RomsListEntry(rom_info.rom_file_path, rom_info.game_system.folder_name, rom_info.display_name)
        self._entries.insert(0, new_entry)
        self._entries_dict[key] = new_entry

        self.save_to_file()
        self.rom_info_list = self.load_entries_as_rom_info()

    def remove_game(self, rom_info: RomInfo):
        key = self._entry_key(rom_info.rom_file_path, rom_info.game_system.folder_name)
        entry = self._entries_dict.pop(key, None)
        if entry:
            self._entries = [e for e in self._entries if self._entry_key(e.rom_file_path, e.game_system_name) != key]

        self.save_to_file()
        self.rom_info_list = self.load_entries_as_rom_info()

    def save_to_file(self):
        try:
            with open(self.entries_file, 'w') as f:
                json.dump(
                    [entry.__dict__ for entry in self._entries],
                    f,
                    indent=4
                )
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to save entries: {e}")

    def load_from_file(self):
        try:
            if not os.path.exists(self.entries_file):
                with open(self.entries_file, 'w') as f:
                    json.dump([], f)

            with open(self.entries_file, 'r') as f:
                data = json.load(f)
                validated_entries = []
                for entry_data in data:
                    entry = RomsListEntry(**entry_data)
                    if os.path.exists(entry.rom_file_path):
                        validated_entries.append(entry)
                    else:
                        PyUiLogger.get_logger().warning(
                            f"ROM file not found, removing from list: {entry.rom_file_path}"
                        )

                self._entries = validated_entries
                self._entries_dict = {
                    self._entry_key(entry.rom_file_path, entry.game_system_name): entry
                    for entry in self._entries
                }

            # Save back the validated list in case some entries were removed
            self.save_to_file()

        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to load entries: {e}")


    def get_games(self) -> List[RomInfo]:
        return self.rom_info_list

    def is_on_list(self, rom_info: RomInfo) -> bool:
        key = self._entry_key(rom_info.rom_file_path, rom_info.game_system.folder_name)
        return key in self._entries_dict

    def load_entries_as_rom_info(self) -> List[RomInfo]:
        rom_info_list: List[RomInfo] = []

        for entry in self._entries:
            try:
                game_system = self.game_system_utils.get_game_system_by_name(entry.game_system_name)
                if game_system is not None:
                    rom_info_list.append(RomInfo(game_system, entry.rom_file_path, entry.display_name))
            except Exception:
                PyUiLogger.get_logger().error(f"Unable to load config for {entry.game_system_name}, skipping entry")

        return rom_info_list

    def sort_alphabetically(self):
        self._entries.sort(key=lambda entry: (entry.display_name or os.path.basename(entry.rom_file_path)).lower())
        # rebuild dict after sorting
        self._entries_dict = {
            self._entry_key(entry.rom_file_path, entry.game_system_name): entry
            for entry in self._entries
        }
        self.save_to_file()
        self.rom_info_list = self.load_entries_as_rom_info()
