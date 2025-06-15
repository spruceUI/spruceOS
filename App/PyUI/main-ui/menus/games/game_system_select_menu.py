
import os
from controller.controller_inputs import ControllerInput
from games.utils.game_system import GameSystem
from games.utils.game_system_utils import GameSystemUtils
from menus.games.game_select_menu import GameSelectMenu
from menus.games.game_system_select_menu_popup import GameSystemSelectMenuPopup
from menus.games.utils.rom_select_options_builder import RomSelectOptionsBuilder
from themes.theme import Theme
from utils.py_ui_config import PyUiConfig
from utils.py_ui_state import PyUiState
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
            "PPSSPP": ["psp"],
            "PSP": ["ppsspp"],
            "PM": ["ports"],
            "SNES": ["sfc"],
            "FFPLAY":["ffplay"],
            "MPV":["ffplay"],
            "WSC":["ws"],
            "FAKE8":["pico","pico8"],
            "FAKE08":["pico","pico8"],
            "PICO8":["pico","pico8"],
            "THIRTYTWOX":["32X"]
        }
        self.full_name_mapping = {
            "32X": "Sega 32X",
            "5200": "Atari 5200",
            "7800": "Atari 7800",
            "amiga": "Amiga",
            "arcade": "Arcade",
            "arduboy": "Arduoboy",
            "atari": "Atari",
            "atari800": "atari800",
            "atarist": "atarist",
            "c64": "Commodore 64",
            "chai": "Chai",
            "col": "Colecovision",
            "cpc": "Amstrad CPC",
            "cps1": "Capcom Play System",
            "cps2": "Capcom Play System 2",
            "cps3": "Capcom Play System 3",
            "dc": "Dreamcast",
            "doom": "Doom",
            "dos": "DOS",
            "easyrpg": "EasyRPG",
            "fairchild": "Fairchild",
            "fc": "Nintendo Entertainment System",
            "fds": "Famicon Disk System",
            "ffplay": "FFplay",
            "gb": "Game Boy",
            "gba": "Game Boy Advance",
            "gbc": "Game Boy Color",
            "gg": "Sega Game Gear",
            "gw": "Game & Watch",
            "itv": "Intellivision",
            "lynx": "Atari Lynx",
            "mame": "Multiple Arcade Machine Emu",
            "md": "Sega Genesis",
            "megaduck": "Mega Duck",
            "ms": "MS",
            "msu1": "Super Nintendo MSU",
            "msumd": "Sega Gensis MSU",
            "msx": "MSX",
            "n64": "Nintendo 64",
            "nds": "Nintendo DS",
            "neocd": "Neo Geo CD",
            "neogeo": "Neo Geo",
            "ngp": "Neo Geo Pocket",
            "ngpc": "Neo Geo Pocket Color",
            "ody": "Magnavox Odyssey 2",
            "openbor": "Open BOR",
            "pce": "TurboGrafx-16",
            "pcecd": "TurboGrafx-CD",
            "pico": "PICO-8",
            "fake08": "FAKE-8",
            "poke": "PokeMini",
            "ports": "Ports",
            "ps": "Playstation",
            "psp": "Playstation Portable",
            "ppsspp": "Playstation Portable",
            "quake": "Quake",
            "satella": "Satellaview",
            "saturn": "Sega Saturn",
            "scummvm": "ScummVM",
            "segacd": "Sega CD",
            "segasgone": "segasgone",
            "sfc": "Super Nintendo",
            "snes": "Super Nintendo",
            "sgb": "Super Gameboy",
            "sgfx": "PC Engine SuperGrafx",
            "sufami": "SuFami Turbo",
            "supervision": "Watara Supervision",
            "tic": "TIC-80 Tiny Computer",
            "vb": "Virtual boy",
            "vdp": "vdp",
            "vectrex": "Vectrex",
            "wolf": "Wolfenstein",
            "ws": "WonderSwan",
            "wsc": "WonderSwan Color",
            "x68000": "X68000",
            "zxs": "ZX Spectrum"
        }
    def get_system_name_for_icon(self, sys_config):        
        if(sys_config.get_icon()):
            return os.path.splitext(os.path.basename(sys_config.get_icon()))[0]
        else:
            return sys_config.get_label().lower()
    
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
        print(f"System_name = {icon_system_name}, folder_name={game_system.folder_name.lower()}")
        icon_system_name_priority = []
        selected_icon_system_name_priority = []

        icon_system_name_priority.append(Theme.get_system_icon(icon_system_name))
        selected_icon_system_name_priority.append(Theme.get_system_icon_selected(icon_system_name))

        icon_system_name_priority.append(Theme.get_system_icon(game_system.folder_name.lower()))
        selected_icon_system_name_priority.append(Theme.get_system_icon_selected(game_system.folder_name.lower()))

        icon_system_name_priority.append(Theme.get_system_icon(game_system.display_name.lower()))
        selected_icon_system_name_priority.append(Theme.get_system_icon_selected(game_system.display_name.lower()))

        if game_system.folder_name in self.common_icon_mappings:
            for name in self.common_icon_mappings.get(game_system.folder_name, []):
                icon_system_name_priority.append(Theme.get_system_icon(name))
                selected_icon_system_name_priority.append(Theme.get_system_icon(name))

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

    def get_rom_count_text(self, game_system):
        roms = RomSelectOptionsBuilder().build_rom_list(game_system, subfolder=None)
        rom_count = len(roms)
        if(rom_count > 1):
               return f"{len(roms)} games"  
        else:
            return f"{len(roms)} game"

    def run_system_selection(self) :
        systems_list = []
        view = None
        active_systems = self.game_utils.get_active_systems()

        index = 0
        total_count = len(active_systems)
        selected = Selection(None,None,0)
        for game_system in active_systems:
            index+=1
            image_path, image_path_selected = self.get_images(game_system)
            icon = image_path_selected
            systems_list.append(
                GridOrListEntry(
                    primary_text=game_system.display_name,
                    primary_text_long=self.full_name_mapping.get(game_system.folder_name.lower()),
                    image_path=image_path,
                    image_path_selected=image_path_selected,
                    description = lambda idx=index, gs=game_system: f"{gs.display_name} - {self.get_rom_count_text(gs)} - System {idx} of {total_count}",
                    icon=icon,
                    value=game_system
                )                
            )
            if(game_system.display_name == PyUiState.get_last_system_selection()):
                selected = Selection(None,None,index-1)

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
                PyUiState.set_last_system_selection(selected.get_selection().get_value().display_name)
                self.rom_select_menu.run_rom_selection(selected.get_selection().get_value())
            elif(ControllerInput.MENU == selected.get_input()):
                self.game_system_select_menu_popup.run_popup_menu_selection(selected.get_selection().get_value())
            elif(ControllerInput.B == selected.get_input() and not Theme.skip_main_menu()):
                exit = True