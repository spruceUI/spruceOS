

import os
from games.utils.game_system import GameSystem 
from menus.games.game_system_config import GameSystemConfig
from utils.logger import PyUiLogger

class GameSystemUtils:
    def __init__(self):
        self.roms_path = "/mnt/SDCARD/Roms/"
        self.emu_path = "/mnt/SDCARD/Emu/"

    def get_active_systems(self) -> list[GameSystem]:
        active_systems : list[GameSystem]= []
        
        # Step 1: Get list of folders in self.emu_path
        try:
            folders = [name for name in os.listdir(self.emu_path)
                    if os.path.isdir(os.path.join(self.emu_path, name))]
        except FileNotFoundError:
            return []  # or handle the error as needed
        
        # Step 2–3: Check if the system is active
        for folder in folders:
            game_system_config = None
            try:
                game_system_config = GameSystemConfig(folder)
            except Exception as e:
                pass

            if(game_system_config is not None):
                display_name = game_system_config.get_label()
                active_systems.append(GameSystem(folder,display_name, game_system_config))

        # Step 4: Sort the list alphabetically
        active_systems.sort(key=lambda system: system.display_name)

        # Step 5: Return the list
        return active_systems
 