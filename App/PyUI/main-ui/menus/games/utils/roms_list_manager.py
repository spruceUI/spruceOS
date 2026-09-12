from dataclasses import dataclass
import json
import os
import tempfile
from pathlib import Path
from typing import List, Tuple
from devices.device import Device
from devices.miyoo.user_config import UserConfig
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

    def get_sort_key(self):
        return sort_key_for_text(self.display_name or os.path.basename(self.rom_file_path).lower() or "")


def sort_key_for_text(text):
    lower = text.lower()
    if(UserConfig.get_ignore_articles_when_sorting()):
        for article in ("the ", "a ", "an "):
            if lower.startswith(article):
                return (text[len(article):] + ", " + article.strip()).lower()

    return lower


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
        key = self._entry_key(rom_info.rom_file_path, rom_info.game_system.system_name)

        if key in self._entries_dict:
            self.remove_game(rom_info)

        new_entry = RomsListEntry(rom_info.rom_file_path, rom_info.game_system.system_name, rom_info.display_name)
        self._entries.insert(0, new_entry)
        self._entries_dict[key] = new_entry

        self.save_to_file()
        self.rom_info_list = self.load_entries_as_rom_info()

    def remove_game(self, rom_info: RomInfo):
        key = self._entry_key(rom_info.rom_file_path, rom_info.game_system.system_name)
        entry = self._entries_dict.pop(key, None)
        if entry:
            self._entries = [e for e in self._entries if self._entry_key(e.rom_file_path, e.game_system_name) != key]

        self.save_to_file()
        self.rom_info_list = self.load_entries_as_rom_info()

    def save_to_file(self):
        # Write to a temp file and swap it in. open(..., 'w') truncates
        # immediately, so a kill between the truncate and the dump leaves a
        # zero byte file behind - and shutdown sends MainUI a SIGKILL, so that
        # window is reachable. Same pattern as device_user_config.save_config.
        tempname = None
        try:
            dirpath = os.path.dirname(self.entries_file) or "."
            # Named after the target so a stray temp left by a hard kill is
            # identifiable in Saves/ rather than an anonymous tmpXXXXXX.
            with tempfile.NamedTemporaryFile(
                'w',
                dir=dirpath,
                prefix=os.path.basename(self.entries_file) + ".",
                suffix=".tmp",
                delete=False
            ) as tmp:
                tempname = tmp.name
                json.dump(
                    [entry.__dict__ for entry in self._entries],
                    tmp,
                    indent=4
                )
                tmp.flush()
                os.fsync(tmp.fileno())
            os.replace(tempname, self.entries_file)
            tempname = None
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to save entries: {e}")
        finally:
            # Do not leave the temp file sitting in Saves/ if the swap failed.
            if tempname is not None:
                try:
                    os.remove(tempname)
                except OSError:
                    pass

    def _read_entries(self):
        # Missing, empty and unparseable all mean "no list yet". They are
        # returned as [] rather than raised, so load_from_file reaches
        # save_to_file and rewrites the file - otherwise a zero byte file
        # fails to parse on every boot and is never repaired.
        if not os.path.exists(self.entries_file):
            return []

        try:
            with open(self.entries_file, 'r') as f:
                contents = f.read()
        except OSError as e:
            PyUiLogger.get_logger().error(f"Unable to read {self.entries_file}: {e}")
            return []

        if not contents.strip():
            PyUiLogger.get_logger().warning(
                f"{self.entries_file} is empty, starting a new list"
            )
            return []

        try:
            data = json.loads(contents)
        except ValueError as e:
            # Unlike an empty file, this may still hold recoverable entries,
            # so keep a copy rather than overwriting it. The shell side does
            # the same in button_actions.sh:update_gameswitcher_json.
            self._back_up_unreadable_file()
            PyUiLogger.get_logger().error(
                f"{self.entries_file} is not valid JSON ({e}), starting a new list"
            )
            return []

        if not isinstance(data, list):
            self._back_up_unreadable_file()
            PyUiLogger.get_logger().error(
                f"{self.entries_file} is not a list, starting a new list"
            )
            return []

        return data

    def _back_up_unreadable_file(self):
        # One fixed suffix, not a timestamp: a repeatedly corrupted file should
        # not accumulate backups in Saves/.
        try:
            os.replace(self.entries_file, self.entries_file + ".corrupt")
        except OSError as e:
            PyUiLogger.get_logger().error(
                f"Unable to back up {self.entries_file}: {e}"
            )

    def load_from_file(self):
        try:
            data = self._read_entries()

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

            # Save back the validated list in case some entries were removed,
            # and to replace a file that could not be read.
            self.save_to_file()

        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to load entries: {e}")


    def get_games(self) -> List[RomInfo]:
        return self.rom_info_list

    def is_on_list(self, rom_info: RomInfo) -> bool:
        key = self._entry_key(rom_info.rom_file_path, rom_info.game_system.system_name)
        return key in self._entries_dict

    def load_entries_as_rom_info(self) -> List[RomInfo]:
        rom_info_list: List[RomInfo] = []

        for entry in self._entries:
            try:
                game_system = self.game_system_utils.get_game_system_by_name(entry.game_system_name)
                if game_system is not None:
                    rom_info_list.append(RomInfo(game_system, entry.rom_file_path, entry.display_name))
            except Exception as e:
                PyUiLogger.get_logger().error(f"Unable to load config for {entry.game_system_name}, skipping entry : {e}")

        return rom_info_list

    def sort_alphabetically(self, display_name_fn=None):
        # display_name_fn lets the caller sort on the name actually shown.
        # Favorites and Recents render the gamelist.xml name now, which is not
        # necessarily the one stored in the entry, and sorting on the stored
        # one would leave the list looking unsorted.
        if display_name_fn is None:
            self._entries.sort(key=lambda entry: (entry.get_sort_key()))
        else:
            def sort_key(entry):
                try:
                    game_system = self.game_system_utils.get_game_system_by_name(entry.game_system_name)
                    if game_system is None:
                        return entry.get_sort_key()
                    return sort_key_for_text(display_name_fn(
                        RomInfo(game_system, entry.rom_file_path, entry.display_name)))
                except Exception as e:
                    PyUiLogger.get_logger().error(f"Unable to sort {entry.rom_file_path}: {e}")
                    return entry.get_sort_key()

            self._entries.sort(key=sort_key)
        # rebuild dict after sorting
        self._entries_dict = {
            self._entry_key(entry.rom_file_path, entry.game_system_name): entry
            for entry in self._entries
        }
        self.save_to_file()
        self.rom_info_list = self.load_entries_as_rom_info()
