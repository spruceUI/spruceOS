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
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.image_list_view import ImageListView
from views.selection import Selection

# Really quickly written just a proof of concept for testing


config = PyUiConfig()
config.load()

selected_theme = os.path.join(config["theme_dir"],config["theme"])
                              
theme = Theme(os.path.join(config["theme_dir"],config["theme"]))

device = MiyooFlip()
display = Display(theme, device)
controller = Controller(device)

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

while(selected is not None):
    img_offset_x = device.screen_width - 10
    img_offset_y = (device.screen_height - display.get_top_bar_height() + display.get_bottom_bar_height())//2 + display.get_top_bar_height() - display.get_bottom_bar_height()
    options_list = ImageListView(display,controller,device,theme, title,
                                option_list, img_offset_x, img_offset_y, theme.rom_image_width, theme.rom_image_height,
                                selected.get_index(), ImageListView.SHOW_ICONS, RenderMode.MIDDLE_RIGHT_ALIGNED,
                                theme.get_list_small_selected_bg())
    selected = options_list.get_selection([ControllerInput.A])
    if(selected is not None):
        if(ControllerInput.A == selected.get_input()):
            subprocess.run(selected.get_selection().get_value(), shell=True)
            selected = None
            sys.exit(0)

sys.exit(1)