
from dataclasses import dataclass
import json
from typing import List
from games.utils.game_system_utils import GameSystemUtils
from menus.games.utils.rom_info import RomInfo
from utils.logger import PyUiLogger

@dataclass
class RomsListEntry:
    rom_file_path: str
    game_system_name: str 
    def __init__(self, rom_file_path, game_system_name):
        self.rom_file_path = rom_file_path
        self.game_system_name = game_system_name

class RomsListManager():
    def __init__(self, entries_file):
        self.entries_file = entries_file
        self._entries: List[RomsListEntry] = []
        self.load_from_file()
        self.game_system_utils = GameSystemUtils()
        self.rom_info_list = self.load_entries_as_rom_info()

    def add_game(self, rom_info: RomInfo):
        new_entry = RomsListEntry(rom_info.rom_file_path, rom_info.game_system.folder_name)
        if any(existing.rom_file_path == new_entry.rom_file_path and existing.game_system_name == new_entry.game_system_name for existing in self._entries):
            self.remove_game(rom_info)
            self._entries.insert(0, new_entry)
        else:
            self._entries.insert(0, new_entry)

        self.save_to_file()
        self.rom_info_list = self.load_entries_as_rom_info()

    def remove_game(self, rom_info: RomInfo):
        to_remove_entry = RomsListEntry(rom_info.rom_file_path, rom_info.game_system.folder_name)
        self._entries = [
            existing for existing in self._entries
            if not (existing.rom_file_path == to_remove_entry.rom_file_path and existing.game_system_name == to_remove_entry.game_system_name)
        ]
        self.save_to_file()
        self.rom_info_list = self.load_entries_as_rom_info()

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
            with open(self.entries_file, 'r') as f:
                data = json.load(f)
                self._entries = [RomsListEntry(**entry) for entry in data]
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to load entries: {e}")

    def get_games(self) -> List[RomInfo]:
        return self.rom_info_list
    
    def is_on_list(self,rom_info):
        return any(existing.rom_file_path == rom_info.rom_file_path and existing.game_system_name == rom_info.game_system.folder_name for existing in self._entries)

    def load_entries_as_rom_info(self) -> List[RomInfo]:
        rom_info_list : List[RomInfo] = []

        #TODO Refactor to use a dict
        for entry in self._entries:
            try:
                game_system = self.game_system_utils.get_game_system_by_name(entry.game_system_name)
                if(game_system is not None):
                    rom_info_list.append(RomInfo(game_system,entry.rom_file_path))
            except Exception:
                PyUiLogger.get_logger().error(f"Unable to load config for {entry.game_system_name} so skipping entry")

        return rom_info_list