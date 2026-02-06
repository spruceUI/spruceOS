

from dataclasses import dataclass
import os

from games.utils.game_system import GameSystem
from menus.games.utils.rom_file_name_utils import RomFileNameUtils


@dataclass
class RomInfo:
    game_system: GameSystem | None
    rom_file_path: str
    is_collection: bool
    display_name: str

    def __init__(self, game_system: GameSystem | None, rom_file_path: str, display_name: str | None = None, is_collection: bool = False):
        self.game_system = game_system
        self.rom_file_path = rom_file_path
        if display_name is None:
            if game_system is not None:
                display_name = RomFileNameUtils.get_rom_name_without_extensions(game_system, rom_file_path)
            else:
                display_name = os.path.basename(rom_file_path)
        self.display_name = display_name
        self.is_collection = is_collection
        
