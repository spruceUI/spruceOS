
import os
import shutil
import sys
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from games.utils.game_system import GameSystem
from menus.games.utils.collections_manager import CollectionsManager
from menus.games.utils.favorites_manager import FavoritesManager
from menus.games.utils.recents_manager import RecentsManager
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.rom_select_options_builder import get_rom_select_options_builder
from utils.logger import PyUiLogger
from utils.user_prompt import UserPrompt
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


from menus.language.language import Language

# Would like this to be generic in the future but this is so Miyoo specific right now 
# Due to the oddities in how its handled
class GameConfigMenu:
    def __init__(self, game_system: GameSystem, game : RomInfo, gen_additional_game_options):
        self.game_system = game_system
        self.game = game
        self.gen_additional_game_options = gen_additional_game_options

    def get_selected_index(self, title, options):
        selected = Selection(None, None, 0)
        self.should_scan_for_bluetooth = True
        option_list = []
        for index, opt in enumerate(options):
            option_list.append(
                GridOrListEntry(
                    primary_text=opt,
                    value=index
                )
            )

        #convert to text and desc and show the theme desc
        #maybe preview too if theyre common
        view = ViewCreator.create_view(
            view_type=ViewType.TEXT_ONLY,
            top_bar_text=title,
            options=option_list,
            selected_index=selected.get_index())

        accepted_inputs = [ControllerInput.A, ControllerInput.B]

        while (True):
            selected = view.get_selection(accepted_inputs)
            if (ControllerInput.A == selected.get_input()):
                return selected.get_selection().get_value()
            elif (ControllerInput.B == selected.get_input()):
                return None
            
    def change_indexed_array_option(self, entry_name, input, rom_file_path, contains_override, all_options, current_value, update_value, update_override, remove_override):
        try:
            selected_index = all_options.index(current_value)
        except:
            selected_index = 0
            PyUiLogger.get_logger().error(f"{current_value} not found in options for {entry_name}")

        PyUiLogger.get_logger().info(f"{current_value} is index {selected_index}")

        if(ControllerInput.X == input or ControllerInput.Y == input):
            if(contains_override):
                PyUiLogger.get_logger().info(f"Removing override {entry_name} for {rom_file_path}")
                remove_override(entry_name,rom_file_path)
            else:
                PyUiLogger.get_logger().info(f"Updating override {entry_name} for {rom_file_path} to {current_value}")
                update_override(entry_name,rom_file_path, current_value)
        else:
            if(ControllerInput.DPAD_LEFT == input):
                selected_index-=1
                if(selected_index < 0):
                    selected_index = len(all_options) -1
            elif(ControllerInput.DPAD_RIGHT == input):
                selected_index+=1
                if(selected_index == len(all_options)):
                    selected_index = 0
            elif(ControllerInput.A == input):
                #selected_index = ThemeSelectionMenu().get_selected_theme_index(theme_folders)
                selected_index = self.get_selected_index(f"Select a {entry_name}", all_options)

            PyUiLogger.get_logger().info(f"{current_value} is updated to index {selected_index}")

            if(selected_index is not None):
                if(contains_override):
                    PyUiLogger.get_logger().info(f"Updating override to {all_options[selected_index]}")
                    update_override(entry_name,rom_file_path, all_options[selected_index])
                else:
                    PyUiLogger.get_logger().info(f"Updating {entry_name} to {all_options[selected_index]}")
                    update_value(entry_name, all_options[selected_index])

    def toggle_overridable_entries(self,input_value, rom_file_path, overridable_entries):
        if(ControllerInput.A == input_value):
            all_overriden = True
            for entry_name in overridable_entries:
                if not self.game_system.game_system_config.contains_menu_override(entry_name,rom_file_path):
                    all_overriden = False
                    break

            for entry_name in overridable_entries:
                if(all_overriden):
                    self.game_system.game_system_config.delete_menu_override(entry_name, rom_file_path)
                else:
                    current_value = self.game_system.game_system_config.get_effective_menu_selection(entry_name,rom_file_path)
                    self.game_system.game_system_config.set_menu_override(entry_name,rom_file_path, current_value)

    def run_launch_option(self, input_value, launch_option):
        if(ControllerInput.A == input_value):

            # Miyoo handles this strangley
            # Example rom /mnt/SDCARD/Roms/PORTS/PokeMMO.sh               
            # example arg /media/sdcard0/Emu/PORTS/../../Roms/PORTS/PokeMMO.sh
            # /media/sdcard0/Emu/PORTS/../../Roms/PORTS/PokeMMO.sh
            # NOTE: Switching to /mnt as it works on brick and flip despite
            # it not being 1:1 it should work out
            game_file_name = os.path.basename(self.game.rom_file_path)
            miyoo_game_path = os.path.join("/mnt/SDCARD/Emu", self.game_system.folder_name, "../../Roms", self.game_system.folder_name, game_file_name)
            Display.deinit_display()

            app_path = launch_option
            if(not os.path.isfile(app_path)):
                app_path = os.path.join("/mnt/SDCARD/Emu", self.game_system.folder_name, launch_option)

            Device.get_device().run_app(os.path.join("/mnt/SDCARD/Emu", self.game_system.folder_name), app_path + " \"" +miyoo_game_path +"\"")
            # TODO Once we remove the display_kill and popups from launch.sh we can remove this
            # For a good speedup
            Display.reinitialize()
            self.game_system.game_system_config.reload_config()

    def delete_rom(self, input_value):
        if(ControllerInput.A == input_value):
            if UserPrompt.prompt_yes_no(Language.delete_rom(), [f"Would you like to permanently delete", f"{self.game.display_name}?"]):
                path = self.game.rom_file_path
                if os.path.isdir(path):
                    shutil.rmtree(path)
                else:
                    os.remove(path)
                self.perform_boxart_deletion()
                Display.display_message(f"{path} deleted.",2000)
                FavoritesManager.remove_favorite(self.game)
                RecentsManager.remove_game(self.game)
                CollectionsManager.remove_game_from_collections(self.game)
                #TODO don't be hackish and reload. Instead remove it from caches
                sys.exit()
    
    def perform_boxart_deletion(self):
        PyUiLogger.get_logger().info(f"Deleting boxart for {self.game.rom_file_path}")
        img_path = get_rom_select_options_builder().get_image_path(self.game)
        while(img_path is not None):
            os.remove(img_path)
            img_path = get_rom_select_options_builder().get_image_path(self.game)
            Display.clear_image_cache()

    def delete_boxart(self, input_value):
        if(ControllerInput.A == input_value):
            if UserPrompt.prompt_yes_no(Language.delete_boxart(), [f"Would you like to permanently delete the boxart for", f"{self.game.display_name}?"]):
                self.perform_boxart_deletion()
                Display.display_message(f"Boxart for {self.game.display_name} deleted.",2000)

    def show_config(self, rom_file_path) :
        self.game_system.game_system_config.reload_config()
        selected = Selection(None, None, 0)
        view = None
        #Loop is weird here due to how these options are handled.
        # We essentially need to re-read the game system config every time
        # an option is selected
        while(selected is not None):

            config_list = []
            if(not Device.get_device().get_system_config().simple_mode_enabled()):
                for config_option in self.game_system.game_system_config.get_launchlist():
                    config_list.append(
                        GridOrListEntry(
                            primary_text=config_option.get('name'),
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=lambda input_value, launch_option=config_option.get('launch')
                                        : self.run_launch_option(input_value,launch_option)

                            
                        )
                    )

            menu_options = self.game_system.game_system_config.get_menu_options()

            if(not Device.get_device().get_system_config().simple_mode_enabled()):

                overridable_entries = []
                for name, option in menu_options.items():
                    devices = option.get("devices")
                    supported_device = not devices or Device.get_device().get_device_name() in devices
                    if(supported_device):
                        effective_value = self.game_system.game_system_config.get_effective_menu_selection(name,rom_file_path)
                        display_name = option.get('display')
                        contains_override = self.game_system.game_system_config.contains_menu_override(name,rom_file_path)
                        if(contains_override):
                            display_name = display_name + "*"
                        
                        overridable_entries.append(name)
                        config_list.append(
                                        GridOrListEntry(
                                        primary_text=display_name,
                                        value_text="<    " + effective_value + "    >",
                                        image_path=None,
                                        image_path_selected=None,
                                        description=None,
                                        icon=None,
                                        value=lambda input_value, entry_name=name, rom_file_path=rom_file_path, contains_override=contains_override, 
                                        all_options=option.get('options', []), current_value=effective_value,
                                            update_value=self.game_system.game_system_config.set_menu_option, update_override=self.game_system.game_system_config.set_menu_override,
                                            remove_override=self.game_system.game_system_config.delete_menu_override
                                            : self.change_indexed_array_option(entry_name, input_value, rom_file_path, contains_override, all_options, current_value, update_value, update_override, remove_override)
                                )
                        )

                if(overridable_entries):
                    config_list.append(
                        GridOrListEntry(
                            primary_text=Language.toggle_settings_as_game_specific_override(),
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=lambda input_value,rom_file_path=rom_file_path, overridable_entries=overridable_entries,
                                        : self.toggle_overridable_entries(input_value,rom_file_path,overridable_entries)
                            )
                        )

            if(not Device.get_device().get_system_config().simple_mode_enabled()):
                config_list.append(
                    GridOrListEntry(
                        primary_text=Language.delete_rom(),
                         value=lambda input_value
                                 : self.delete_rom(input_value)
                    )
                )                
                config_list.append(
                    GridOrListEntry(
                        primary_text=Language.delete_boxart(),
                        value=lambda input_value
                                : self.delete_boxart(input_value)
                    )
                )


            config_list.extend(self.gen_additional_game_options())

            if(view is None):        
                view = ViewCreator.create_view(
                    view_type=ViewType.ICON_AND_DESC,
                    top_bar_text=self.game_system.display_name + " Configuration", 
                    options=config_list,
                    selected_index=selected.get_index())
            else:
                view.set_options(config_list)

            expected_inputs = [ControllerInput.A, ControllerInput.DPAD_LEFT, ControllerInput.DPAD_RIGHT, ControllerInput.B, ControllerInput.X, ControllerInput.Y]
            selected = view.get_selection(expected_inputs)

            if(ControllerInput.B == selected.get_input()):
                selected = None
            elif(selected.get_input() is not None):
                selected.get_selection().get_value()(selected.get_input()) 
                if(not os.path.exists(self.game.rom_file_path)):
                    selected = None