import json
import os
import subprocess
import sys
from controller.controller_inputs import ControllerInput
from display.render_mode import RenderMode
import sdl2
import sdl2.ext

from menus.main_menu import MainMenu
from controller.controller import Controller
from display.display import Display
from themes.theme import Theme
from devices.miyoo_flip import MiyooFlip
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.image_list_view import ImageListView
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType

# Really quickly written just a proof of concept for testing

PyUiLogger.init("/mnt/SDCARD/Saves/spruce/OptionSelectUI.log", "OptionSelectUI")

config = PyUiConfig()
config.load()

selected_theme = os.path.join(config["themeDir"],config["theme"])
                              
theme = Theme(os.path.join(config["themeDir"],config["theme"]))

device = MiyooFlip()
display = Display(theme, device)
controller = Controller(device, config)
view_creator = ViewCreator(display,controller,device,theme)

title = sys.argv[1]
input_json = sys.argv[2]


selected = Selection(None,None,0)
# Regenerate as part of while loop in case the options menu changes anything
with open(input_json, "r", encoding="utf-8") as f:
    data = json.load(f)

option_list = []
for entry in data:
    option_list.append(
        GridOrListEntry(
            primary_text=entry.get("primary_text"),
            image_path=entry.get("image_path"),
            image_path_selected=entry.get("image_path_selected"),
            description=entry.get("description"),
            icon=entry.get("icon"),
            value=entry.get("value")
        )
    )

view = view_creator.create_view(
        view_type=ViewType.TEXT_AND_IMAGE_LIST_VIEW,
        top_bar_text=title,
        options=option_list, 
        selected_index=selected.get_index())

while(True):
    selected = view.get_selection([ControllerInput.A])
    if(selected is not None):
        if(ControllerInput.A == selected.get_input()):
            subprocess.run(selected.get_selection().get_value(), shell=True)
            selected = None
            sys.exit(0)
        elif(ControllerInput.B == selected.get_input()):
            sys.exit(1)

