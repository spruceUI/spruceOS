import argparse
import os
from pathlib import Path
import shutil
import signal
import sys
import threading
from devices.device import Device
from devices.miyoo.system_config import SystemConfig
from menus.app.hidden_apps_manager import AppsManager
from menus.games.utils.collections_manager import CollectionsManager
from menus.games.utils.favorites_manager import FavoritesManager
from menus.games.utils.recents_manager import RecentsManager
from menus.language.language import Language
import sdl2
import sdl2.ext

from menus.main_menu import MainMenu
from controller.controller import Controller
from display.display import Display
from themes.theme import Theme
from utils.cfw_system_config import CfwSystemConfig
from utils.config_copier import ConfigCopier
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from utils.py_ui_state import PyUiState



def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('-logDir', type=str, default='/mnt/SDCARD/pyui/logs/', help='Directory to store logs')
    parser.add_argument('-pyUiConfig', type=str, default='/mnt/SDCARD/Saves/pyui-config.json', help='Location of PyUI config')
    parser.add_argument('-device', type=str, default='MIYOO_FLIP', help='The device type (MIYOO_FLIP or TRIMUI_BRICK)')
    parser.add_argument('-cfwConfig', type=str, default=None, help='Path to the systems json config')
    parser.add_argument('-msgDisplay', type=str, default=None, help='A message to display and then exit')
    parser.add_argument('-msgDisplayTimeMs', type=str, default=None, help='How long to display the message')
    parser.add_argument('-msgDisplayRealtime', type=str, default=None, help='Reads from stdin to display messages')
    return parser.parse_args()

def log_renderer_info():
    num = sdl2.SDL_GetNumRenderDrivers()
    for i in range(num):
        info = sdl2.SDL_RendererInfo()
        sdl2.SDL_GetRenderDriverInfo(i, info)
        print(f"Found Renderer {i}: {info.name.decode()}")

    num = sdl2.SDL_GetNumVideoDrivers()
    for i in range(num):
        print(f"Found Video Decoder {i}: {sdl2.SDL_GetVideoDriver(i).decode()}")

def initialize_device(device):
    if "MIYOO_FLIP" == device or "SPRUCE_MIYOO_FLIP" == device:
        from devices.miyoo.flip.miyoo_flip import MiyooFlip
        Device.init(MiyooFlip(device))
    elif "MIYOO_MINI_FLIP" == device or "SPRIG_MIYOO_MINI_FLIP" == device:
        from devices.miyoo.mini_flip.miyoo_mini_flip import MiyooMiniFlip
        Device.init(MiyooMiniFlip(device))
    elif "TRIMUI_BRICK" == device or "SPRUCE_TRIMUI_BRICK" == device:
        from devices.trimui.trim_ui_brick import TrimUIBrick
        Device.init(TrimUIBrick(device))
    elif "TRIMUI_SMART_PRO" == device or "SPRUCE_TRIMUI_SMART_PRO" == device:
        from devices.trimui.trim_ui_smart_pro import TrimUISmartPro
        Device.init(TrimUISmartPro(device))
    elif "MIYOO_A30" == device or "SPRUCE_MIYOO_A30" == device:
        from devices.miyoo.flip.miyoo_a30 import MiyooA30
        Device.init(MiyooA30(device))
    elif "ANBERNIC_RG34XXSP" == device:
        from devices.muos.muos_anbernic_rgxx import MuosAnbernicRGXX
        Device.init(MuosAnbernicRGXX(device))
    elif "ANBERNIC_RG28XX" == device:
        from devices.muos.muos_anbernic_rgxx import MuosAnbernicRGXX
        Device.init(MuosAnbernicRGXX(device))
    elif "ANBERNIC_MUOS" == device:
        from devices.muos.muos_anbernic_rgxx import MuosAnbernicRGXX
        Device.init(MuosAnbernicRGXX(device))
    else:
        raise RuntimeError(f"{device} is not a supported device")


def background_startup():
    FavoritesManager.initialize(Device.get_favorites_path())
    RecentsManager.initialize(Device.get_recents_path())
    CollectionsManager.initialize(Device.get_collections_path())
    AppsManager.initialize(Device.get_apps_config_path())

def start_background_threads():
    startup_thread = threading.Thread(target=Device.perform_startup_tasks)
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
                    image_path = message[len("RENDER_IMAGE:"):].strip()
                    PyUiLogger.get_logger().info(f"Rendering image from path: {image_path}")
                    Display.display_image(image_path)
                else:
                    Display.display_message(message)
                    
        except Exception as e:
            PyUiLogger.get_logger().error("Error processing messages: ", exc_info=True)
        PyUiLogger.get_logger().info(f"Exitting...")
        sys.exit(0)

def main():
    args = parse_arguments()

    PyUiLogger.init(args.logDir, "PyUI")
    PyUiLogger.get_logger().info(f"logDir: {args.logDir}")
    PyUiLogger.get_logger().info(f"pyUiConfig: {args.pyUiConfig}")
    PyUiLogger.get_logger().info(f"device: {args.device}")

    log_renderer_info()

    verify_config_exists(args.pyUiConfig)
    PyUiConfig.init(args.pyUiConfig)
    CfwSystemConfig.init(args.cfwConfig)

    initialize_device(args.device)
    PyUiState.init(Device.get_state_path())

    selected_theme = os.path.join(PyUiConfig.get("themeDir"), Device.get_system_config().get_theme())
    PyUiLogger.get_logger().info(f"{selected_theme}")

    Theme.init(selected_theme, Device.screen_width(), Device.screen_height())
    Display.init()
    #2nd init is just to allow scaling if needed
    Theme.convert_theme_if_needed(selected_theme, Device.screen_width(), Device.screen_height())
    Display.clear_image_cache()
    Display.clear_text_cache()
    Controller.init()
    Language.init()

    check_for_msg_display(args)
    check_for_msg_display_realtime(args)
    
    main_menu = MainMenu()

    start_background_threads()

    main_menu.run_main_menu_selection()


def sigterm_handler(signum, frame):
    print(f"Received SIGTERM (Signal {signum}). Shutting down...")
    sys.exit(0) # Exit gracefully

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, sigterm_handler)
    main()
    os._exit(0)
