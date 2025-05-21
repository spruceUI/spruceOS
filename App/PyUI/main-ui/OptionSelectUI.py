import json
import os
import subprocess
import sys
from controller.controller_inputs import ControllerInput
from devices.device import Device
import sdl2
import sdl2.ext

from controller.controller import Controller
from display.display import Display
from themes.theme import Theme
from devices.miyoo.flip.miyoo_flip import MiyooFlip
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType

# Really quickly written just a proof of concept for testing

PyUiLogger.init("/mnt/SDCARD/Saves/spruce/", "OptionSelectUI")

PyUiConfig.init("/mnt/SDCARD/App/PyUI/py-ui-config.json")

selected_theme = os.path.join(PyUiConfig.get("themeDir"),PyUiConfig.get("theme"))
                              

Device.init(MiyooFlip())
Theme.init(os.path.join(PyUiConfig.get("themeDir"),PyUiConfig.get("theme")), Device.screen_width(), Device.screen_height())

Display.init()
Controller.init()

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

view = ViewCreator.create_view(
        view_type=ViewType.TEXT_AND_IMAGE,
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

