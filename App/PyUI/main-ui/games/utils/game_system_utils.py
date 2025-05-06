

import os

class GameSystemUtils:
    def __init__(self):
        self.roms_path = "/mnt/SDCARD/Roms/"
        self.emu_path = "/mnt/SDCARD/Emu/"


    def is_system_active(self, folder):
        config_path = os.path.join(self.emu_path,folder, "config.json")
        if not os.path.isfile(config_path):
            return False

        try:
            with open(config_path, "r", encoding="utf-8") as f:
                first_chars = f.read(2)
                return first_chars != "{{"
        except Exception:
            return False
        
    def get_active_systems(self):
        active_systems = []
        
        # Step 1: Get list of folders in self.emu_path
        try:
            folders = [name for name in os.listdir(self.emu_path)
                    if os.path.isdir(os.path.join(self.emu_path, name))]
        except FileNotFoundError:
            return []  # or handle the error as needed
        
        # Step 2–3: Check if the system is active
        for folder in folders:
            if self.is_system_active(folder):
                active_systems.append(folder)
        
        # Step 4: Sort the list alphabetically
        active_systems.sort()

        # Step 5: Return the list
        return active_systems
 