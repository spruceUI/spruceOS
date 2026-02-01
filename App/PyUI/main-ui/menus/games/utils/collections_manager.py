
from dataclasses import dataclass
import json
import os
import threading
from typing import List
from devices.device import Device
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.roms_list_manager import RomsListEntry
from utils.logger import PyUiLogger


@dataclass
class CollectionEntry:
    collection_name: str
    game_list: List[RomsListEntry] 
    def __init__(self, collection_name, game_list):
        self.collection_name = collection_name
        self.game_list = game_list
        
class CollectionsManager:
    _collections: List[CollectionEntry] = []
    _collections_file_name = "collections.json"
    _init_event = threading.Event()  # signals when initialize() has been called

    @classmethod
    def initialize(cls, _collections_folder: str):
        cls._game_system_utils = Device.get_device().get_game_system_utils()
        cls._collections_folder = _collections_folder
        cls.load_from_file()
        cls._init_event.set()  # unblock waiting methods

    @classmethod
    def _wait_for_init(cls):
        cls._init_event.wait()  # blocks until initialize() happens

    @classmethod
    def convert_to_rom_list_entry(cls, rom_info):
        cls._wait_for_init()
        return RomsListEntry(rom_info.rom_file_path, rom_info.game_system.folder_name)

    @classmethod
    def load_entries_as_rom_info(cls, game_list) -> List['RomInfo']:
        cls._wait_for_init()
        rom_info_list: List['RomInfo'] = []

        for entry in game_list:
            try:
                game_system = cls._game_system_utils.get_game_system_by_name(entry.game_system_name)
                if game_system is not None:
                    rom_info_list.append(RomInfo(game_system, entry.rom_file_path))
            except Exception:
                PyUiLogger.get_logger().error(
                    f"Unable to load config for {entry.game_system_name} so skipping entry"
                )
                
        # Sort by filename (case-insensitive)
        rom_info_list.sort(key=lambda rom: os.path.basename(rom.rom_file_path).lower())

        return rom_info_list

    @classmethod
    def load_from_file(cls):
        cls._collections = []
        file_path = os.path.join(cls._collections_folder, cls._collections_file_name)

        # Ensure the parent folders exist
        os.makedirs(os.path.dirname(file_path), exist_ok=True)

        if not os.path.exists(file_path):
            # If file doesn't exist, initialize it as empty
            with open(file_path, 'w') as f:
                json.dump([], f)
            return

        try:
            with open(file_path, 'r') as f:
                data = json.load(f)
                for coll in data:
                    game_list = [
                        RomsListEntry(game["rom_file_path"], game["game_system_name"])
                        for game in coll["game_list"]
                    ]
                    cls._collections.append(CollectionEntry(coll["collection_name"], game_list))
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to load collections file: {e}")
            cls._collections = []

    @classmethod
    def save_to_file(cls):
        cls._wait_for_init()
        os.makedirs(cls._collections_folder, exist_ok=True)
        file_path = os.path.join(cls._collections_folder, cls._collections_file_name)

        data = [
            {
                "collection_name": coll.collection_name,
                "game_list": [
                    {
                        "rom_file_path": game.rom_file_path,
                        "game_system_name": game.game_system_name,
                    }
                    for game in coll.game_list
                ],
            }
            for coll in cls._collections
        ]

        try:
            with open(file_path, 'w') as f:
                json.dump(data, f, indent=4)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to save collections file: {e}")

    @classmethod
    def create_collection(cls, collection_name):
        cls._wait_for_init()
        if not any(c.collection_name == collection_name for c in cls._collections):
            cls._collections.append(CollectionEntry(collection_name, []))
            cls.save_to_file()
            cls.load_from_file()

    @classmethod
    def delete_collection(cls, collection_name):
        cls._wait_for_init()
        cls._collections = [
            c for c in cls._collections if c.collection_name != collection_name
        ]
        cls.save_to_file()
        cls.load_from_file()

    @classmethod
    def add_game_to_collection(cls, collection_name, rom_info: 'RomInfo'):
        cls._wait_for_init()
        for coll in cls._collections:
            if coll.collection_name == collection_name:
                # Prevent duplicate entries
                if not any(g.rom_file_path == rom_info.rom_file_path for g in coll.game_list):
                    coll.game_list.append(cls.convert_to_rom_list_entry(rom_info))
                break
        else:
            # If collection doesn't exist, create it and add the game
            cls._collections.append(
                CollectionEntry(collection_name, [cls.convert_to_rom_list_entry(rom_info)])
            )

        cls.save_to_file()
        cls.load_from_file()

    @classmethod
    def remove_from_collection(cls, collection_name, rom_info: 'RomInfo'):
        cls._wait_for_init()
        for coll in cls._collections:
            if coll.collection_name == collection_name:
                coll.game_list = [
                    g for g in coll.game_list if g.rom_file_path != rom_info.rom_file_path
                ]
                if not coll.game_list:
                    cls._collections.remove(coll)
                break
        
        cls.save_to_file()
        cls.load_from_file()

    @classmethod
    def get_collection_names(cls):
        cls._wait_for_init()
        return [c.collection_name for c in cls._collections]

    @classmethod
    def get_games_in_collection(cls, collection_name):
        cls._wait_for_init()
        for coll in cls._collections:
            if coll.collection_name == collection_name:
                return cls.load_entries_as_rom_info(coll.game_list)
        return []
    
    @classmethod
    def get_collections_containing_rom(cls, rom_file_path: str) -> List[str]:
        cls._wait_for_init()
        matching_collections = []
        for coll in cls._collections:
            if any(game.rom_file_path == rom_file_path for game in coll.game_list):
                matching_collections.append(coll.collection_name)
        return matching_collections
    
    @classmethod
    def get_collections_not_containing_rom(cls, rom_file_path: str) -> List[str]:
        cls._wait_for_init()
        matching_collections = []
        for coll in cls._collections:
            if not any(game.rom_file_path == rom_file_path for game in coll.game_list):
                matching_collections.append(coll.collection_name)
        return matching_collections
    
    @classmethod
    def remove_game_from_collections(cls, rom_info: RomInfo):
        cls._wait_for_init()

        to_delete = []

        # Remove this ROM from all collections
        for coll in cls._collections:
            original_len = len(coll.game_list)

            coll.game_list = [
                g for g in coll.game_list if g.rom_file_path != rom_info.rom_file_path
            ]

            # If this collection became empty, mark it for deletion
            if original_len > 0 and len(coll.game_list) == 0:
                to_delete.append(coll)

        # Delete empty collections
        for coll in to_delete:
            cls._collections.remove(coll)

        # Save and reload
        cls.save_to_file()
        cls.load_from_file()

