from abc import ABC, abstractmethod
from menus.games.utils.rom_info import RomInfo


class RomAppSetup(ABC):

    @abstractmethod
    def run_game(self, device, rom_info: RomInfo):
        pass

    @abstractmethod
    def run_cmd(self, device, args, dir = None, is_power_cmd = False):
        pass
    
    @abstractmethod
    def run_app(self, device, folder,launch):
        pass
    
    @abstractmethod
    def get_image_for_activity(self, activity):
        pass

    @abstractmethod
    def get_app_finder(self):
        pass
