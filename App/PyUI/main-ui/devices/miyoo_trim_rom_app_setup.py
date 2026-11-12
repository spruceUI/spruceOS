from devices.rom_app_setup import RomAppSetup
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
    
    # Same key resolution as get_selected_emulator, which the launcher mirrors, plus the per-game override
    def get_core_for_game(self, device, game_system_config, rom_file_path):
        menu_options = game_system_config.get_menu_options()
        arch_key = device.get_emulator_arch(menu_options, rom_file_path)
        for key, option in menu_options.items():
            if key.startswith("Emulator") and (arch_key is None or key == arch_key) and any(name in (option.get("devices") or []) for name in device.get_device_names()):
                return game_system_config.get_effective_menu_selection(key, rom_file_path)
        return game_system_config.get_effective_menu_selection("Emulator", rom_file_path)

    # Same suffixed state folder names the TrimUI and Miyoo classes check; a missing one is just a failed exists()
    def get_core_name_overrides(self, core_name):
        return [core_name, core_name + "-64", core_name + "-32"]
