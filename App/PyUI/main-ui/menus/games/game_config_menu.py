
import os
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from games.utils.game_system import GameSystem
from menus.games.utils.rom_info import RomInfo
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


# Would like this to be generic in the future but this is so Miyoo specific right now 
# Due to the oddities in how its handled
class GameConfigMenu:
    def __init__(self, game_system: GameSystem, game : RomInfo):
        self.game_system = game_system
        self.game = game

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
                        value=config_option.get('launch')
                    )
                )
            if(view is None):        
                view = ViewCreator.create_view(
                    view_type=ViewType.ICON_AND_DESC,
                    top_bar_text=self.game_system.display_name + " Configuration", 
                    options=config_list,
                    selected_index=selected.get_index())
            else:
                view.set_options(config_list)

            selected = view.get_selection()

            if(ControllerInput.A == selected.get_input()):
                # Miyoo handles this strangley
                # Example rom /mnt/SDCARD/Roms/PORTS/PokeMMO.sh               
                # example arg /media/sdcard0/Emu/PORTS/../../Roms/PORTS/PokeMMO.sh
                #/media/sdcard0/Emu/PORTS/../../Roms/PORTS/PokeMMO.sh
                game_file_name = os.path.basename(self.game.rom_file_path)
                miyoo_game_path = os.path.join("/media/sdcard0/Emu", self.game_system.folder_name, "../../Roms", self.game_system.folder_name, game_file_name)
                Display.deinit_display()

                app_path = selected.get_selection().get_value()
                if(not os.path.isfile(app_path)):
                    app_path = os.path.join("/media/sdcard0/Emu", self.game_system.folder_name, selected.get_selection().get_value())

                Device.run_app(["sh",app_path, miyoo_game_path], dir=os.path.join("/media/sdcard0/Emu", self.game_system.folder_name))
                # TODO Once we remove the display_kill and popups from launch.sh we can remove this
                # For a good speedup
                Display.reinitialize()
                self.game_system.game_system_config.reload_config()
            elif(ControllerInput.B == selected.get_input()):
                selected = None