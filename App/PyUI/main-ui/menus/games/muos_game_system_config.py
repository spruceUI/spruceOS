import json
import os

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
        return '/mnt/sdcard/Emu/muos_launch.sh'

    def get_extlist(self):
        return RomFolders.get_extensions(self.system_name)

    def get_launchlist(self):
        return []
    
    def run_in_game_menu(self):
        return "PORTS" == self.label
    
    def subfolder_launch_file(self):
        return None
