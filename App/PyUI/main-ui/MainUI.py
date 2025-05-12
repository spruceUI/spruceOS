from multiprocessing import get_logger
import os
import threading
import sdl2
import sdl2.ext

from menus.main_menu import MainMenu
from controller.controller import Controller
from display.display import Display
from themes.theme import Theme
from devices.miyoo_flip import MiyooFlip
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig


PyUiLogger.init("/mnt/SDCARD/Saves/spruce/pyui.log", "PyUI")

config = PyUiConfig()
config.load()

selected_theme = os.path.join(config["themeDir"],config["theme"])
                              
PyUiLogger.get_logger().info(f"{selected_theme}")

theme = Theme(os.path.join(config["themeDir"],config["theme"]))

device = MiyooFlip()
display = Display(theme, device)
controller = Controller(device, config)

main_menu = MainMenu(display, controller, device, theme, config)

startup_thread = threading.Thread(target=device.perform_startup_tasks())
startup_thread.start()

main_menu.run_main_menu_selection()
