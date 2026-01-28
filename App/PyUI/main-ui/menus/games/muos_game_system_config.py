import os
import sys

from menus.games.utils.rom_extensions import RomFolders

class MuosGameSystemConfig():
    def __init__(self, display_name, system_name):
        self.system_name = system_name
        self.label = display_name
        self.icon = None
        self.iconsel = None

    def reload_config(self):
        pass
    def __str__(self):
        return f"MuosGameSystemConfig(system_name='{self.system_name}')"
    
    def get_emu_folder(self):
        return self.system_name

    def get_label(self):
        return self.label

    def get_icon(self):
        return self.icon

    def get_icon_selected(self):
        return self.iconsel

    def get_launch(self):
        base_dir = os.path.abspath(sys.path[0])
        return os.path.join(base_dir, "devices","muos", "muos_launch.sh")

    def get_extlist(self):
        return RomFolders.get_extensions(self.system_name)

    def get_launchlist(self):
        return []
    
    def run_in_game_menu(self):
        return str(self.label).lower() == "ports"

    def uses_retroarch(self):
        lower_label = str(self.label).lower()
        return "ports" != lower_label and "psp" != lower_label
    
    
    def subfolder_launch_file(self):
        return None

    def get_cpu_options(self):
        return []
    
    def get_selected_cpu(self):
        return None
    
    def get_core_options(self):
        return []
    
    def get_selected_core(self):
        return None
            
    def scan_subfolders(self):
        return True
        
