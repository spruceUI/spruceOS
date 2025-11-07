import json
import os
import subprocess
import sys
from controller.controller_inputs import ControllerInput

from display.display import Display
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType

class OptionSelectUI:

    @staticmethod
    def display_option_list(title, input_json):
        selected = Selection(None,None,0)
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
                    Display.deinit_display()
                    sys.exit(0)
                elif(ControllerInput.B == selected.get_input()):
                    Display.deinit_display()
                    sys.exit(1)

