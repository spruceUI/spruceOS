import argparse
import os
from pathlib import Path
import signal
import sys
import threading
from devices.device import Device
from devices.miyoo.mini.miyoo_mini_flip_specific_model_variables import MIYOO_MINI_FLIP_VARIABLES, MIYOO_MINI_PLUS, MIYOO_MINI_V1_V2_V3_VARIABLES, MIYOO_MINI_V4_VARIABLES
from menus.app.hidden_apps_manager import AppsManager
from menus.games.utils.collections_manager import CollectionsManager
from menus.games.utils.custom_gameswitcher_list_manager import CustomGameSwitcherListManager
from menus.games.utils.favorites_manager import FavoritesManager
from menus.games.utils.recents_manager import RecentsManager
from menus.language.language import Language
from option_select_ui import OptionSelectUI
import sdl2
import sdl2.ext

from menus.main_menu import MainMenu
from controller.controller import Controller
from display.display import Display
from themes.theme import Theme
from utils.button_listener import ButtonListener
from utils.cfw_system_config import CfwSystemConfig
from utils.config_copier import ConfigCopier
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from utils.py_ui_state import PyUiState
from utils.realtime_message_network_listener import RealtimeMessageNetworkListener
from utils.time_logger import log_timing



def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('-logDir', type=str, default='/mnt/SDCARD/pyui/logs/', help='Directory to store logs')
    parser.add_argument('-pyUiConfig', type=str, default='/mnt/SDCARD/Saves/pyui-config.json', help='Location of PyUI config')
    parser.add_argument('-device', type=str, default='MIYOO_FLIP', help='The device type (MIYOO_FLIP or TRIMUI_BRICK)')
    parser.add_argument('-cfwConfig', type=str, default=None, help='Path to the systems json config')
    parser.add_argument('-msgDisplay', type=str, default=None, help='A message to display and then exit')
    parser.add_argument('-msgDisplayTimeMs', type=str, default=None, help='How long to display the message')
    parser.add_argument('-msgDisplayRealtime', type=str, default=None, help='Reads from stdin to display messages')
    parser.add_argument('-msgDisplayRealtimePort', type=str, default=None, help='Reads from the passed in port to display messages')
    parser.add_argument('-optionListFile', type=str, default=None, help='Runs in a mode to just display a list of options')
    parser.add_argument('-optionListTitle', type=str, default=None, help='Title to display if option list is provided')
    parser.add_argument('-buttonListenerMode', type=str, default=None, help='Just run and output button presses')
    parser.add_argument('-startupInitOnly', type=str, default=None, help='Only run startup sequences for the device')
    return parser.parse_args()

def log_renderer_info():
    num = sdl2.SDL_GetNumRenderDrivers()
    for i in range(num):
        info = sdl2.SDL_RendererInfo()
        sdl2.SDL_GetRenderDriverInfo(i, info)
        PyUiLogger.get_logger().info(f"Found Renderer {i}: {info.name.decode()}")

    num = sdl2.SDL_GetNumVideoDrivers()
    for i in range(num):
        PyUiLogger.get_logger().info(f"Found Video Decoder {i}: {sdl2.SDL_GetVideoDriver(i).decode()}")

def initialize_device(device, main_ui_mode):
    if "MIYOO_FLIP" == device or "SPRUCE_MIYOO_FLIP" == device:
        from devices.miyoo.flip.miyoo_flip import MiyooFlip
        Device.init(MiyooFlip(device, main_ui_mode))
    elif "MIYOO_MINI" == device:
        from devices.miyoo.mini.miyoo_mini_common import MiyooMiniCommon
        Device.init(MiyooMiniCommon(device,main_ui_mode,MIYOO_MINI_V1_V2_V3_VARIABLES))
    elif "MIYOO_MINI_V4" == device:
        from devices.miyoo.mini.miyoo_mini_common import MiyooMiniCommon
        Device.init(MiyooMiniCommon(device,main_ui_mode,MIYOO_MINI_V4_VARIABLES))
    elif "MIYOO_MINI_PLUS" == device:
        from devices.miyoo.mini.miyoo_mini_common import MiyooMiniCommon
        Device.init(MiyooMiniCommon(device,main_ui_mode,MIYOO_MINI_PLUS))
    elif "MIYOO_MINI_FLIP" == device:
        from devices.miyoo.mini.miyoo_mini_common import MiyooMiniCommon
        Device.init(MiyooMiniCommon(device,main_ui_mode,MIYOO_MINI_FLIP_VARIABLES))
    elif "SPRIG_MIYOO_MINI" == device:
        from devices.miyoo.mini.sprig_miyoo_mini_common import SprigMiyooMiniCommon
        Device.init(SprigMiyooMiniCommon(device, main_ui_mode,MIYOO_MINI_V1_V2_V3_VARIABLES))
    elif "SPRIG_MIYOO_MINI_V4" == device:
        from devices.miyoo.mini.sprig_miyoo_mini_common import SprigMiyooMiniCommon
        Device.init(SprigMiyooMiniCommon(device, main_ui_mode,MIYOO_MINI_V4_VARIABLES))
    elif "SPRIG_MIYOO_MINI_PLUS" == device:
        from devices.miyoo.mini.sprig_miyoo_mini_common import SprigMiyooMiniCommon
        Device.init(SprigMiyooMiniCommon(device, main_ui_mode,MIYOO_MINI_PLUS))
    elif "SPRIG_MIYOO_MINI_FLIP" == device:
        from devices.miyoo.mini.sprig_miyoo_mini_common import SprigMiyooMiniCommon
        Device.init(SprigMiyooMiniCommon(device, main_ui_mode,MIYOO_MINI_FLIP_VARIABLES))
    elif "TRIMUI_BRICK" == device or "SPRUCE_TRIMUI_BRICK" == device:
        from devices.trimui.trim_ui_brick import TrimUIBrick
        Device.init(TrimUIBrick(device,main_ui_mode))
    elif "TRIMUI_SMART_PRO" == device or "SPRUCE_TRIMUI_SMART_PRO" == device:
        from devices.trimui.trim_ui_smart_pro import TrimUISmartPro
        Device.init(TrimUISmartPro(device,main_ui_mode))
    elif "TRIMUI_SMART_PRO_S" == device or "SPRUCE_TRIMUI_SMART_PRO_S" == device:
        from devices.trimui.trim_ui_smart_pro_s import TrimUISmartProS
        Device.init(TrimUISmartProS(device,main_ui_mode))
    elif "MIYOO_A30" == device or "SPRUCE_MIYOO_A30" == device:
        from devices.miyoo.a30.miyoo_a30 import MiyooA30
        Device.init(MiyooA30(device, main_ui_mode))
    elif "ANBERNIC_RG34XXSP" == device:
        from devices.muos.muos_anbernic_rgxx import MuosAnbernicRGXX
        Device.init(MuosAnbernicRGXX(device))
    elif "ANBERNIC_RG28XX" == device:
        from devices.muos.muos_anbernic_rgxx import MuosAnbernicRGXX
        Device.init(MuosAnbernicRGXX(device))
    elif "ANBERNIC_MUOS" == device:
        from devices.muos.muos_anbernic_rgxx import MuosAnbernicRGXX
        Device.init(MuosAnbernicRGXX(device))        
    elif "GKD_PIXEL2" == device:
        from devices.gkd.gkd_pixel2 import GKDPixel2
        Device.init(GKDPixel2(device, main_ui_mode))
    else:
        raise RuntimeError(f"{device} is not a supported device")


def background_startup():
    FavoritesManager.initialize(Device.get_device().get_favorites_path())
    RecentsManager.initialize(Device.get_device().get_recents_path())
    CustomGameSwitcherListManager.initialize()
    CollectionsManager.initialize(Device.get_device().get_collections_path())
    AppsManager.initialize(Device.get_device().get_apps_config_path())

def start_background_threads():
    startup_thread = threading.Thread(target=Device.get_device().perform_startup_tasks)
    startup_thread.start()

    # Background favorites/recents init thread
    background_thread = threading.Thread(target=background_startup)
    background_thread.start()

def verify_config_exists(config_path):
    # Determine the directory where this script resides
    script_dir = Path(__file__).resolve().parent
    source = script_dir / 'config.json'

    ConfigCopier.ensure_config(config_path, source)

def check_for_msg_display(args):
    if(args.msgDisplay):
        duration = 2000
        if(args.msgDisplayTimeMs):
            try:
                duration = int(args.msgDisplayTimeMs)
            except Exception as e:
                PyUiLogger.get_logger().error(f"Error parsing message duration: ", exc_info=True)

        try:
            Display.display_message(args.msgDisplay, duration)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error displaying message: ", exc_info=True)

        sys.exit(0)

def check_for_option_list_file(args):
    if(args.optionListFile):
        OptionSelectUI.display_option_list(args.optionListTitle,args.optionListFile, True)

def check_for_msg_display_realtime(args):
    if(args.msgDisplayRealtime):
        try:
            for line in sys.stdin:
                PyUiLogger.get_logger().info(f"Waiting on next message")
                message = line.strip()
                PyUiLogger.get_logger().info(f"Received Message : {message}")
                if message == "EXIT_APP":
                    break

                if message.startswith("RENDER_IMAGE:"):
                    option_list_file = message[len("RENDER_IMAGE:"):].strip()
                    PyUiLogger.get_logger().info(f"Rendering image from path: {option_list_file}")
                    Display.display_image(option_list_file)
                elif message.startswith("OPTION_LIST:"):
                    option_list_file = message[len("OPTION_LIST:"):].strip()
                    PyUiLogger.get_logger().info(f"Option list file: {option_list_file}")
                    OptionSelectUI.display_option_list("",option_list_file, False)
                else:
                    Display.display_message(message)
                    
        except Exception as e:
            PyUiLogger.get_logger().error("Error processing messages: ", exc_info=True)
        PyUiLogger.get_logger().info(f"Exitting...")
        sys.exit(0)

def check_for_msg_display_socket_based(args):
    if(args.msgDisplayRealtimePort):
        RealtimeMessageNetworkListener(args.msgDisplayRealtimePort).start()

def check_for_button_listener_mode(args):
    if(args.buttonListenerMode):
        print("Running in button listener mode")
        ButtonListener().start()

def check_for_startup_init_only(args):
    if(args.startupInitOnly):
        print("Running in startup init only mode")
        Device.get_device().startup_init(include_wifi=False)
        sys.exit(0)

def main():
    args = parse_arguments()
    PyUiLogger.init(args.logDir, "PyUI")
    PyUiLogger.get_logger().info(f"{args}")

    #log_renderer_info()

    with log_timing("Entire Startup initialization", PyUiLogger.get_logger()):    

        with log_timing("Config initialization", PyUiLogger.get_logger()):    
            verify_config_exists(args.pyUiConfig)
            PyUiConfig.init(args.pyUiConfig)
            CfwSystemConfig.init(args.cfwConfig)

        main_ui_mode = True

        if(args.msgDisplayRealtime or args.msgDisplay or args.msgDisplayRealtimePort or args.optionListFile or args.buttonListenerMode):
            main_ui_mode = False

        with log_timing("Device initialization", PyUiLogger.get_logger()):    
            initialize_device(args.device, main_ui_mode)

        PyUiState.init(Device.get_device().get_state_path())

        selected_theme = os.path.join(PyUiConfig.get("themeDir"), Device.get_device().get_system_config().get_theme())
        check_for_button_listener_mode(args)
        check_for_startup_init_only(args)

        with log_timing("Theme initialization", PyUiLogger.get_logger()):    
            Theme.init(selected_theme, Device.get_device().screen_width(), Device.get_device().screen_height())

        with log_timing("Display initialization", PyUiLogger.get_logger()):    
            Display.init()
        with log_timing("Display Present", PyUiLogger.get_logger()):    
            Display.present()
        
        #2nd init is just to allow scaling if needed
        Theme.convert_theme_if_needed(selected_theme, Device.get_device().screen_width(), Device.get_device().screen_height())
        Controller.init()
        Language.init()

        Device.get_device().perform_sdcard_ro_check()

        check_for_msg_display(args)
        check_for_msg_display_realtime(args)
        check_for_msg_display_socket_based(args)
        check_for_option_list_file(args)

    main_menu = MainMenu()

    start_background_threads()
    keep_running = True
    PyUiLogger.get_logger().info("Entering main loop")
    while(keep_running):
        try:
            main_menu.run_main_menu_selection()
        except Exception as e:
            PyUiLogger.get_logger().exception("Unhandled exception occurred")
            PyUiState.clear()
            sys.exit()

def sigterm_handler(signum, frame):
    PyUiLogger.get_logger().info(f"Received SIGTERM (Signal {signum}). Shutting down...")
    sys.exit() # Exit gracefully

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, sigterm_handler)
    main()
    os._exit(0)
