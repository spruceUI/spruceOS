

import os
from games.game_system_utils import GameSystemUtils
from games.utils.game_system import GameSystem 
from games.utils.rom_utils import RomUtils
from menus.games.file_based_game_system_config import FileBasedGameSystemConfig
from utils.logger import PyUiLogger

class MiyooTrimGameSystemUtils(GameSystemUtils):
    def __init__(self):
        self.roms_path = "/mnt/SDCARD/Roms/"
        self.emu_path = "/mnt/SDCARD/Emu/"
        if(not os.path.exists(self.emu_path)):
            self.emu_path =  "/mnt/SDCARD/Emus/"
        PyUiLogger().get_logger().info(f"Emu folder is {self.emu_path}")
        self.rom_utils = RomUtils(self.roms_path)
    
    def get_game_system_by_name(self, system_name) -> GameSystem:
        game_system_config = FileBasedGameSystemConfig(system_name)

        if(game_system_config is not None):
            display_name = game_system_config.get_label()
            return GameSystem(self.roms_path+system_name,display_name, game_system_config)

        PyUiLogger.get_logger().error(f"Unable to load game system for {system_name}")
        return None

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
                game_system_config = FileBasedGameSystemConfig(folder)
            except Exception as e:
                #PyUiLogger().get_logger().info(f"{folder} contains a broken config.json : {e}")
                pass

            if(game_system_config is not None and self.contains_needed_files(game_system_config)):
                display_name = game_system_config.get_label()
                game_system = GameSystem(os.path.join(self.roms_path, folder),display_name, game_system_config)
                if(self.rom_utils.has_roms(game_system)):
                    active_systems.append(game_system)

        # Step 4: Sort the list alphabetically
        active_systems.sort(key=lambda system: system.display_name)

        # Step 5: Return the list
        return active_systems
 
    def contains_needed_files(self, game_system_config):
        required_files_groups = game_system_config.required_files_groups()

        # If there are no required files, we consider it valid
        if not required_files_groups:
            return True

        for group in required_files_groups:
            # Ensure at least one file in the group exists
            if not any(os.path.exists(file_path) for file_path in group):
                # Log which group is missing
                missing_files = ", ".join(group)
                PyUiLogger.get_logger().error(
                    f"Missing required files: none of these exist [{missing_files}]"
                )
                return False  # This group failed
        
        return True  # All groups passed