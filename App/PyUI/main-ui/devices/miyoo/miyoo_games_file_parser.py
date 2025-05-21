import json
import os

from games.utils.game_entry import GameEntry
from utils.logger import PyUiLogger

class MiyooGamesFileParser:

    def __init__(self):
        pass

    def parse_recents(self):
        return self._parse('/mnt/SDCARD/Roms/recentlist.json')

    def parse_favorites(self):
        return self._parse('/mnt/SDCARD/Roms/favourite.json')

    def _parse(self, file_path):
        # List to hold the parsed JSON objects
        entries = []
        try:
            with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
                for line in f:
                    line = line.strip()
                    if line:  # Ignore empty lines
                        try:
                            data = json.loads(line)
                            if(os.path.isfile(data['rompath']) and data['launch'].endswith("standard_launch.sh")):
                                entry = GameEntry(
                                    label=data['label'],
                                    launch=data['launch'],
                                    rom_path=data['rompath'],
                                    type=data['type']
                                )
                                entries.append(entry)
                        except (json.JSONDecodeError, UnicodeDecodeError) as e:
                            PyUiLogger.get_logger().error(f"Error parsing line: {line}\n{e}")
        except (FileNotFoundError, IOError) as e:
            PyUiLogger.get_logger().error(f"Could not read favorites file: {e}")
        return entries
