import os
import threading
import sdl2
import sdl2.ext

from menus.main_menu import MainMenu
from controller.controller import Controller
from display.display import Display
from themes.theme import Theme
from devices.miyoo_flip import MiyooFlip
from utils.py_ui_config import PyUiConfig

config = PyUiConfig()
config.load()

selected_theme = os.path.join(config["theme_dir"],config["theme"])
                              
print(f"{selected_theme}")

theme = Theme(os.path.join(config["theme_dir"],config["theme"]))

device = MiyooFlip()
display = Display(theme, device)
controller = Controller(device)

main_menu = MainMenu(display, controller, device, theme, config)

startup_thread = threading.Thread(target=device.perform_startup_tasks())
startup_thread.start()

main_menu.run_main_menu_selection()
