

import os
from devices.device import Device
from games.game_system_utils import GameSystemUtils
from games.utils.game_system import GameSystem 
from games.utils.rom_utils import RomUtils
from menus.games.file_based_game_system_config import FileBasedGameSystemConfig
from menus.games.utils.rom_file_name_utils import RomFileNameUtils
from menus.games.utils.rom_info import RomInfo
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class MiyooTrimGameSystemUtils(GameSystemUtils):
    CORE_TO_FOLDER_LOOKUP = {
        "2048": ["2048"],
        "81": ["81"],
        "a5200": ["a5200"],
        "ardens": ["Ardens"],
        "atari800": ["Atari800"],
        "bk": ["bk"],
        "bluemsx": ["blueMSX"],
        "cap32": ["Caprice32"],
        "chailove": ["ChaiLove"],
        "chimerasnes": ["ChimeraSNES"],
        "crocods": ["CrocoDS"],
        "daphne": ["Daphne"],
        "dosbox_pure": ["DOSBox"],
        "duckstation": ["DuckStation"],
        "easyrpg": ["EasyRPG Player"],
        "ecwolf": ["ECWolf"],
        "fake08": ["FAKE-08","fake-08"],
        "fbalpha2012": ["FB Alpha 2012"],
        "fbneo": ["FinalBurn Neo"],
        "fceumm": ["FCEUmm"],
        "flycast": ["Flycast"],
        "fmsx": ["fMSX"],
        "freechaf": ["FreeChaF"],
        "freeintv": ["FreeIntv"],
        "frodo": ["Frodo"],
        "fuse": ["Fuse"],
        "gambatte": ["Gambatte"],
        "gearboy": ["Gearboy"],
        "gearcoleco": ["Gearcoleco"],
        "gearsystem": ["Gearsystem"],
        "genesis_plus_gx": ["Genesis Plus GX"],
        "gme": ["Game Music Emu"],
        "gpsp": ["gpSP"],
        "gw": ["GW"],
        "handy": ["Handy"],
        "hatari": ["Hatari"],
        "km_duckswanstation_xtreme_amped": ["DuckSwanStation Xtreme Amped"],
        "km_flycast_xtreme": ["Flycast Xtreme"],
        "km_ludicrousn64_2k22_xtreme_amped": ["LudicrousN64 2K22 Xtreme Amped"],
        "km_parallel_n64_xtreme_amped_turbo": ["ParaLLEl N64 Xtreme Amped Turbo"],
        "libgametank": ["GameTank (Rust)"],
        "lowresnx": ["lowresnx"],
        "lutro": ["Lutro"],
        "mame2003_plus": ["MAME 2003-Plus"],
        "mame2003_xtreme": ["mame2003_xtreme"],
        "mednafen_lynx": ["Beetle Lynx"],
        "mednafen_ngp": ["Beetle NeoPop"],
        "mednafen_pce_fast": ["Beetle PCE Fast"],
        "mednafen_pce": ["Beetle PCE"],
        "mednafen_pcfx": ["Beetle PC-FX"],
        "mednafen_supafaust": ["Beetle Supafaust", "Supafaust"],
        "mednafen_supergrafx": ["Beetle SuperGrafx"],
        "mednafen_vb": ["Beetle VB"],
        "mednafen_wswan": ["Beetle WonderSwan"],
        "mgba": ["mGBA"],
        "mu": ["Mu"],
        "neocd": ["NeoCD"],
        "nestopia": ["Nestopia"],
        "np2kai": ["Neko Project II"],
        "numero": ["Numero"],
        "o2em": ["O2EM"],
        "opera": ["Opera"],
        "parallel_n64": ["ParaLLEl N64"],
        "pcsx_rearmed": ["PCSX-ReARMed"],
        "picodrive": ["PicoDrive"],
        "pokemini": ["PokeMini"],
        "potator": ["Potator"],
        "ppsspp": ["PPSSPP"],
        "prboom": ["PrBoom"],
        "prosystem": ["ProSystem"],
        "puae2021": ["PUAE 2021"],
        "puzzlescript": ["puzzlescript"],
        "px68k": ["PX68k"],
        "quasi88": ["QUASI88"],
        "quicknes": ["QuickNES"],
        "race": ["RACE"],
        "reminiscence": ["REminiscence"],
        "retro8": ["Retro8"],
        "sameduck": ["SameDuck"],
        "scummvm": ["ScummVM"],
        "snes9x2002": ["Snes9x 2002"],
        "snes9x2005": ["Snes9x 2005"],
        "snes9x2005_plus": ["Snes9x 2005 Plus"],
        "snes9x2010": ["Snes9x 2010"],
        "snes9x": ["Snes9x"],
        "squirreljme": ["SquirrelJME"],
        "stella2014": ["Stella 2014"],
        "swanstation": ["SwanStation"],
        "tgbdual": ["TGB Dual"],
        "theodore": ["theodore"],
        "tic80": ["TIC-80"],
        "tyrquake": ["TyrQuake"],
        "uae4arm": ["UAE4ARM"],
        "uw8": ["MicroW8"],
        "uzem": ["uzem"],
        "vecx": ["vecx"],
        "vemulator": ["VeMUlator"],
        "vice_x64": ["VICE x64"],
        "vice_xvic": ["VICE xvic"],
        "x1": ["x1"],
        "yabasanshiro": ["YabaSanshiro"]
    }

    def __init__(self):
        self.roms_paths = ["/mnt/SDCARD/Roms/"]
        self.emu_path = "/mnt/SDCARD/Emu/"
        if(not os.path.exists(self.emu_path)):
            self.emu_path =  "/mnt/SDCARD/Emus/"
            
        if(os.path.exists("/media/sdcard1/Roms/")):
            self.roms_paths.append("/media/sdcard1/Roms/")
        self.rom_utils = RomUtils(self.roms_paths[0])

    def get_game_system_by_name(self, system_name) -> GameSystem:
        game_system_config = FileBasedGameSystemConfig(system_name)

        if(game_system_config is not None):
            display_name = game_system_config.get_label()
            return GameSystem(self.build_paths_array(system_name),display_name, game_system_config)

        PyUiLogger.get_logger().error(f"Unable to load game system for {system_name}")
        return None

    def build_paths_array(self, system_name):
        # Build a copy of self.roms_paths with the system_name appended to each path
        return [
            full_path for full_path in (os.path.join(path, system_name) for path in self.roms_paths)
            if os.path.isdir(full_path)
        ]
    def get_active_systems(self) -> list[GameSystem]:
        active_systems : list[GameSystem]= []
        
        # Step 1: Get list of folders in self.emu_path
        try:
            folders = [name for name in os.listdir(self.emu_path)
                    if os.path.isdir(os.path.join(self.emu_path, name))]
        except FileNotFoundError:
            return []  # or handle the error as needed
        
        # Step 2–3: Check if the system is active
        for folder in folders:
            game_system_config = None
            try:
                game_system_config = FileBasedGameSystemConfig(folder)
            except Exception as e:
                #PyUiLogger().get_logger().info(f"{folder} contains a broken config.json : {e}")
                pass

            if(game_system_config is not None 
               and (self.contains_needed_files(game_system_config) 
                                                   or PyUiConfig.show_all_game_systems())):
                devices = game_system_config.get_devices()
                supported_device = not devices or Device.get_device().get_device_name() in devices
                if(supported_device):
                    folder_paths = self.build_paths_array(folder)
                    if(len(folder_paths) > 0):
                        display_name = game_system_config.get_label()
                        game_system = GameSystem(folder_paths,display_name, game_system_config)
                        if(PyUiConfig.show_all_game_systems() or self.rom_utils.has_roms(game_system)):
                            active_systems.append(game_system)

        # Step 4: Sort the list alphabetically
        if("Alphabetical" == PyUiConfig.game_system_sort_mode()):        
            active_systems.sort(key=lambda system: system.display_name)
        elif("SortOrderKey" == PyUiConfig.game_system_sort_mode()):
            active_systems.sort(key=lambda system: system.sort_order)
        elif("Custom" == PyUiConfig.game_system_sort_mode()):
            # Get priorities (1 = highest priority, 3 = lowest)
            type_priority = PyUiConfig.game_system_sort_type_priority()
            brand_priority = PyUiConfig.game_system_sort_brand_priority()
            year_priority = PyUiConfig.game_system_sort_year_priority()
            name_priority = PyUiConfig.game_system_sort_name_priority()

            # Create a mapping from priority to the field accessor
            priority_order = {
                type_priority: lambda s: s.type,
                brand_priority: lambda s: s.brand,
                year_priority: lambda s: s.release_year,
                name_priority: lambda s: s.display_name,
            }

            # Sort using a tuple key ordered by priority, then display_name
            active_systems.sort(
                key=lambda s: (
                    priority_order[1](s),
                    priority_order[2](s),
                    priority_order[3](s),
                    priority_order[4](s),
                )
            )

        # Step 5: Return the list
        return active_systems
 
    def contains_needed_files(self, game_system_config):
        required_files_groups = game_system_config.required_files_groups()

        # If there are no required files, we consider it valid
        if not required_files_groups:
            return True

        for group in required_files_groups:
            # Ensure at least one file in the group exists
            if not any(os.path.exists(file_path) for file_path in group):
                # Log which group is missing
                missing_files = ", ".join(group)
                PyUiLogger.get_logger().warning(
                    f"{game_system_config.system_name} is missing required files: none of these exist [{missing_files}]"
                )
                return False  # This group failed
        
        return True  # All groups passed
    
    def check_for_image_with_core(self, core, saves_root, base_name, rom_info):
        if(core is not None):
            state_png = os.path.join(saves_root, core, base_name + ".state.auto.png")
            if os.path.exists(state_png):
                #PyUiLogger.get_logger().info(f"Found Save state image {state_png}, rom_file: {rom_info.rom_file_path}")
                return state_png
            else:
                #PyUiLogger.get_logger().warning(f"Save state image not found at {state_png}, core: {core}, rom_file: {rom_info.rom_file_path}")
                return None

    def get_save_state_image(self, rom_info: RomInfo):
        # Get the base filename without extension
        # Normalize and split the path into components
        parts = os.path.normpath(rom_info.rom_file_path).split(os.sep)
        try:
            roms_index = next(i for i, part in enumerate(parts) if part.lower() == "roms")
        except (ValueError, IndexError):
            PyUiLogger.get_logger().info(f"Roms not found in {rom_info.rom_file_path}")
            return None  # "Roms" not in path or nothing after "Roms"

        saves_root = os.sep.join(parts[:roms_index]) + os.sep + "Saves" + os.sep + "states"
        base_name = RomFileNameUtils.get_rom_name_without_extensions(rom_info.game_system, rom_info.rom_file_path)

    
        core_selection_in_config = Device.get_device().get_core_for_game(rom_info.game_system.game_system_config, os.path.basename(rom_info.rom_file_path))
       
        core_names = self.CORE_TO_FOLDER_LOOKUP.get(core_selection_in_config)
        if(core_names is not None):       
            for core in core_names:
                cores_to_try = Device.get_device().get_core_name_overrides(core)
            
                for core_to_try in cores_to_try:
                    state_png = self.check_for_image_with_core(core_to_try, saves_root, base_name, rom_info)
                    if(state_png is not None):
                        return state_png
        else:
            #PyUiLogger.get_logger().warning(f"{rom_info.rom_file_path} : No core mapping found for emulator {core_selection_in_config}, emu: {rom_info.game_system.display_name}")
            pass

        # This is SPRUCE specific but shouldn't add much slowdown / create issues as a fallback
        return self.check_for_image_with_core(".gameswitcher", saves_root, base_name, rom_info)
