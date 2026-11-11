from devices import RomAppSetup
from menus.games.utils.rom_info import RomInfo
from devices.miyoo_trim_common import MiyooTrimCommon
from apps.miyoo.miyoo_app_finder import MiyooAppFinder


class MiyooTrimRomAppSetup(RomAppSetup):

    def run_game(self, device, rom_info: RomInfo):
        MiyooTrimCommon.run_game(device, rom_info)

    def run_cmd(self, device, args, dir = None, is_power_cmd = False):
        MiyooTrimCommon.run_cmd(device, args, dir, is_power_cmd)
            
    def run_app(self, device, folder,launch):
        MiyooTrimCommon.run_app(device, folder,launch)

    def get_image_for_activity(self, activity):
        return MiyooTrimCommon.get_image_for_activity(activity)
    
    def get_app_finder(self):
        return MiyooAppFinder()
