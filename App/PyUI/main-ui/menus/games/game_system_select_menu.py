
from controller.controller import Controller
from devices.device import Device
from display.display import Display
from games.utils.game_system_utils import GameSystemUtils
from menus.games.game_select_menu import GameSelectMenu
from menus.games.game_system_config import GameSystemConfig
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.grid_view import GridView


class GameSystemSelectMenu:
    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme):
        self.display : Display= display
        self.controller : Controller = controller
        self.device : Device= device
        self.theme : Theme= theme
        self.game_utils : GameSystemUtils = GameSystemUtils()
        self.rom_select_menu : GameSelectMenu = GameSelectMenu(display,controller,device,theme)
        self.use_emu_cfg = False

    def run_system_selection(self) :
        selected = "new"
        systems_list = []
        for system in self.game_utils.get_active_systems():
            sysConfig = GameSystemConfig(system)
            if(self.use_emu_cfg):
                systems_list.append(
                    GridOrListEntry(
                        primary_text=system,
                        image_path=sysConfig.get_icon(),
                        image_path_selected=sysConfig.get_icon_selected(),
                        description="Game System",
                        icon=sysConfig.get_icon_selected(),
                        value=system
                    ) 
                )
            else:
                systems_list.append(
                    GridOrListEntry(
                        primary_text=system,
                        image_path=self.theme.get_system_icon(system),
                        image_path_selected=self.theme.get_system_icon_selected(system),
                        description="Game System",
                        icon=self.theme.get_system_icon_selected(system),
                        value=system
                    )                
                )

        options_list = GridView(self.display,self.controller,self.device,self.theme, "Game", systems_list, 4, 2,
                                self.theme.system_selected_bg())
        while((selected := options_list.get_selection()) is not None):
            self.rom_select_menu.run_rom_selection(selected.get_selection().get_primary_text())
