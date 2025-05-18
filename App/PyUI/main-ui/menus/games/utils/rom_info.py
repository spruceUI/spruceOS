

from dataclasses import dataclass

from games.utils.game_system import GameSystem


@dataclass
class RomInfo:
    game_system: GameSystem
    rom_file_path: str
    def __init__(self, game_system: GameSystem, rom_file_path: str):
        self.game_system = game_system
        self.rom_file_path = rom_file_path
