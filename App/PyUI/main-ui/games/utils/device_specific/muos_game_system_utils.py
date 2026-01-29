

import os
from games.game_system_utils import GameSystemUtils
from games.utils.game_system import GameSystem 
from games.utils.rom_utils import RomUtils
from menus.games.file_based_game_system_config import FileBasedGameSystemConfig
from menus.games.muos_game_system_config import MuosGameSystemConfig
from utils.logger import PyUiLogger

class MuosGameSystemUtils(GameSystemUtils):
    def __init__(self, muos_systems):
        self.roms_path = "/mnt/union/ROMS/"
        self.emu_path = "/mnt/SDCARD/Emu/"

        self.rom_utils = RomUtils(self.roms_path)
        self.muos_systems = muos_systems 

    def get_game_system_by_name(self, system_name) -> GameSystem:
        game_system_config = MuosGameSystemConfig(system_name,system_name)

        if(game_system_config is not None):
            display_name = game_system_config.get_label()
            return GameSystem([system_name],display_name, game_system_config)

        PyUiLogger.get_logger().error(f"Unable to load game system for {system_name}")
        return None


    def get_active_systems(self) -> list[GameSystem]:
        active_systems : list[GameSystem]= []
        
        # Step 1: Get list of folders in self.roms_path
        try:
            folders = [name for name in os.listdir(self.roms_path)
                    if os.path.isdir(os.path.join(self.roms_path, name))]
        except FileNotFoundError:
            return []  # or handle the error as needed
        
        # Step 2–3: Check if the system is active
        for folder in folders:
            game_system_config = None
            try:
                if os.path.isdir(os.path.join(self.emu_path, folder)):
                    game_system_config = FileBasedGameSystemConfig(folder)
                elif folder.upper() in self.muos_systems:
                    game_system_config = MuosGameSystemConfig(folder,self.muos_systems[folder.upper()])

            except Exception as e:
                pass
            
            if(game_system_config is not None):
                display_name = game_system_config.get_label()
                game_system = GameSystem([os.path.join(self.roms_path, folder)],display_name, game_system_config)
                if(self.rom_utils.has_roms(game_system)):
                    active_systems.append(game_system)


        # Step 4: Sort the list alphabetically
        active_systems.sort(key=lambda system: system.display_name)

        # Step 5: Return the list
        return active_systems
 