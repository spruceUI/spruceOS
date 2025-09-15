

from dataclasses import dataclass

from games.utils.game_system import GameSystem


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
        self.is_collection = is_collection
        
