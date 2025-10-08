
import os
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from games.utils.game_system import GameSystem
from menus.games.utils.rom_info import RomInfo
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


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
            
    def change_indexed_array_option(self, input, all_options, current_value, update_value):
        try:
            selected_index = all_options.index(current_value)
        except:
            selected_index = 0

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
            selected_index = self.get_selected_index("Select a Core", all_options)

        if(selected_index is not None):
            PyUiLogger.get_logger().info(f"Updating core to {all_options[selected_index]}")
            update_value(all_options[selected_index])

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

            Device.run_cmd(["sh",app_path, miyoo_game_path], dir=os.path.join("/mnt/SDCARD/Emu", self.game_system.folder_name))
            # TODO Once we remove the display_kill and popups from launch.sh we can remove this
            # For a good speedup
            Display.reinitialize()
            self.game_system.game_system_config.reload_config()

    def show_config(self) :
        selected = Selection(None, None, 0)
        view = None
        #Loop is weird here due to how these options are handled.
        # We essentially need to re-read the game system config every time
        # an option is selected
        while(selected is not None):

            config_list = []
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

            config_list.extend(self.gen_additional_game_options())

            core_options = self.game_system.game_system_config.get_core_options()
            cpu_options = self.game_system.game_system_config.get_cpu_options()

            if(len(core_options) > 0):
                config_list.append(
                        GridOrListEntry(
                                primary_text="Emu Core",
                                value_text="<    " + self.game_system.game_system_config.get_selected_core() + "    >",
                                image_path=None,
                                image_path_selected=None,
                                description=None,
                                icon=None,
                                value=lambda input_value, all_options=core_options, current_value=self.game_system.game_system_config.get_selected_core(), update_value=self.game_system.game_system_config.set_selected_core
                                    : self.change_indexed_array_option(input_value, all_options, current_value, update_value)
                        )
                    )
            else:
                PyUiLogger.get_logger().info(f"No core options found in config")

            if(len(cpu_options) > 0):
                config_list.append(
                        GridOrListEntry(
                                primary_text="CPU Governor",
                                value_text="<    " + self.game_system.game_system_config.get_selected_cpu() + "    >",
                                image_path=None,
                                image_path_selected=None,
                                description=None,
                                icon=None,
                                value=lambda input_value, all_options=cpu_options, current_value=self.game_system.game_system_config.get_selected_cpu(), update_value=self.game_system.game_system_config.set_selected_cpu
                                    : self.change_indexed_array_option(input_value, all_options, current_value, update_value)
                        )
                    )
            else:
                PyUiLogger.get_logger().info(f"No core options found in config")


            if(view is None):        
                view = ViewCreator.create_view(
                    view_type=ViewType.ICON_AND_DESC,
                    top_bar_text=self.game_system.display_name + " Configuration", 
                    options=config_list,
                    selected_index=selected.get_index())
            else:
                view.set_options(config_list)

            expected_inputs = [ControllerInput.A, ControllerInput.DPAD_LEFT, ControllerInput.DPAD_RIGHT, ControllerInput.B]
            selected = view.get_selection(expected_inputs)

            if(ControllerInput.A == selected.get_input() or ControllerInput.DPAD_LEFT == selected.get_input() or ControllerInput.DPAD_RIGHT == selected.get_input()):
                PyUiLogger.get_logger().info(f"DPAD LEFT OR RIGHT CALLED")
                selected.get_selection().get_value()(selected.get_input()) 
            elif(ControllerInput.B == selected.get_input()):
                selected = None
                