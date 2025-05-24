
import os
from controller.controller_inputs import ControllerInput
from games.utils.game_system import GameSystem
from games.utils.game_system_utils import GameSystemUtils
from menus.games.game_select_menu import GameSelectMenu
from menus.games.game_system_select_menu_popup import GameSystemSelectMenuPopup
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator


class GameSystemSelectMenu:
    def __init__(self):
        self.game_utils : GameSystemUtils = GameSystemUtils()
        self.rom_select_menu : GameSelectMenu = GameSelectMenu()
        self.use_emu_cfg = False
        self.game_system_select_menu_popup = GameSystemSelectMenuPopup()
        self.common_icon_mappings = {
            "PPSSPP": "psp",
            "FFPLAY":"ffplay",
            "MPV":"ffplay",
            "WSC":"ws",
            "FAKE8":"pico",
            "PICO8":"pico",
            "THIRTYTWOX":"32X"
        }

    def get_system_name_for_icon(self, sys_config):        
        return os.path.splitext(os.path.basename(sys_config.get_icon()))[0]
    
    def get_first_existing_path(self,icon_system_name_priority):
        for index, path in enumerate(icon_system_name_priority):
            try:
                if path and os.path.isfile(path):
                    return index
            except Exception:
                pass
        return None 

    def get_images(self, game_system : GameSystem):
        icon_system_name = self.get_system_name_for_icon(game_system.game_system_config)
        icon_system_name_priority = []
        selected_icon_system_name_priority = []

        icon_system_name_priority.append(Theme.get_system_icon(icon_system_name))
        selected_icon_system_name_priority.append(Theme.get_system_icon_selected(icon_system_name))

        icon_system_name_priority.append(Theme.get_system_icon(game_system.folder_name.lower()))
        selected_icon_system_name_priority.append(Theme.get_system_icon_selected(game_system.folder_name.lower()))

        icon_system_name_priority.append(Theme.get_system_icon(game_system.display_name.lower()))
        selected_icon_system_name_priority.append(Theme.get_system_icon_selected(game_system.display_name.lower()))

        if game_system.folder_name in self.common_icon_mappings:
            icon_system_name_priority.append(Theme.get_system_icon(self.common_icon_mappings[game_system.folder_name]))
            selected_icon_system_name_priority.append(Theme.get_system_icon_selected(self.common_icon_mappings[game_system.folder_name]))

        if(game_system.game_system_config.get_icon() is not None):
            icon_system_name_priority.append(os.path.join(game_system.game_system_config.get_emu_folder(),game_system.game_system_config.get_icon()))

            if(game_system.game_system_config.get_icon_selected() is not None):
                selected_icon_system_name_priority.append(os.path.join(game_system.game_system_config.get_emu_folder(),game_system.game_system_config.get_icon_selected()))
            else:
                selected_icon_system_name_priority.append(os.path.join(game_system.game_system_config.get_emu_folder(),game_system.game_system_config.get_icon()))
        
        index = self.get_first_existing_path(icon_system_name_priority)
        if(index is not None):
            icon = icon_system_name_priority[index]
            selected_icon = selected_icon_system_name_priority[index]
            if not os.path.isfile(selected_icon):
                selected_icon = icon    
            return icon, selected_icon
        else:
            return None, None
    
    def run_system_selection(self) :
        selected = Selection(None,None,0)
        systems_list = []
        view = None
        for game_system in self.game_utils.get_active_systems():
            image_path, image_path_selected = self.get_images(game_system)
            icon = image_path_selected
            systems_list.append(
                GridOrListEntry(
                    primary_text=game_system.display_name,
                    image_path=image_path,
                    image_path_selected=image_path_selected,
                    description="Game System",
                    icon=icon,
                    value=game_system
                )                
            )
        if(view is None):
            view = ViewCreator.create_view(
                view_type=Theme.get_view_type_for_system_select_menu(),
                top_bar_text="Game", 
                options=systems_list, 
                cols=Theme.get_game_system_select_col_count(), 
                rows=Theme.get_game_system_select_row_count(),
                selected_index=selected.get_index(),
                use_mutli_row_grid_select_as_backup_for_single_row_grid_select=Theme.get_system_select_show_sel_bg_grid_mode(),
                hide_grid_bg=not Theme.get_system_select_show_sel_bg_grid_mode(),
                show_grid_text=Theme.get_system_select_show_text_grid_mode()
            )
        else:
            view.set_options(systems_list)

        exit = False
        while(not exit):
            selected = view.get_selection([ControllerInput.A, ControllerInput.MENU])
            if(ControllerInput.A == selected.get_input()):
                self.rom_select_menu.run_rom_selection(selected.get_selection().get_value())
            elif(ControllerInput.MENU == selected.get_input()):
                self.game_system_select_menu_popup.run_popup_menu_selection(selected.get_selection().get_value())
            elif(ControllerInput.B == selected.get_input()):
                exit = True