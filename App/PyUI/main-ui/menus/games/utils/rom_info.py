

from dataclasses import dataclass
import os

from games.utils.game_system import GameSystem
from menus.games.utils.rom_file_name_utils import RomFileNameUtils


@dataclass
class RomInfo:
    game_system: GameSystem
    rom_file_path: str
    is_collection: bool
    display_name: str

    def __init__(self, game_system: GameSystem, rom_file_path: str, display_name=None, is_collection=False):
        self.game_system = game_system
        self.rom_file_path = rom_file_path
        self.display_name = display_name
        if(self.display_name is None):
            self.display_name = RomFileNameUtils.get_rom_name_without_extensions(game_system,rom_file_path)
        self.is_collection = is_collection
        
