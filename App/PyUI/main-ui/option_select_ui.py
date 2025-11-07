from collections import defaultdict
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

"""
Sample Input
{
    "A/Z/Q": "touch /mnt/SDCARD/q",
    "A/Z/R": "touch /mnt/SDCARD/R",
    "A/Y/S/T": "touch /mnt/SDCARD/T",
    "A/Y/S/U": "touch /mnt/SDCARD/U",
    "B/M": "touch /mnt/SDCARD/M",
    "B/N": "touch /mnt/SDCARD/N",
    "C": "touch /mnt/SDCARD/C",
    "D/E/F": "touch /mnt/SDCARD/F",
    "D/G": "touch /mnt/SDCARD/G"
}
"""
class OptionSelectUI:

    @staticmethod
    def display_option_list(title, input_json):
        # --- Load JSON file ---
        with open(input_json, "r", encoding="utf-8") as f:
            data = json.load(f)

        # --- Convert flat paths into nested dict ---
        def tree():
            return defaultdict(tree)
        root = tree()

        for key, value in data.items():
            parts = key.split("/")
            node = root
            for part in parts[:-1]:
                node = node[part]
            node[parts[-1]] = value  # leaf value = path string

        # --- Recursive menu navigation ---
        def navigate_menu(menu_dict, title, is_root=False):
            if isinstance(menu_dict, str):
                # Should never happen (we only call navigate_menu on dicts)
                return

            option_list = []
            for key, val in menu_dict.items():
                option_list.append(
                    GridOrListEntry(
                        primary_text=key,
                        value=key
                    )
                )

            selected = Selection(None, None, 0)
            view = ViewCreator.create_view(
                view_type=ViewType.TEXT_ONLY,
                top_bar_text=title,
                options=option_list,
                selected_index=selected.get_index()
            )

            while True:
                selected = view.get_selection([ControllerInput.A, ControllerInput.B])
                if selected is None:
                    continue

                inp = selected.get_input()
                entry = selected.get_selection()

                if inp == ControllerInput.B:
                    if is_root:
                        Display.deinit_display()
                        sys.exit(1)
                    else:
                        return None  # go up a level

                elif inp == ControllerInput.A:
                    key = entry.get_value()
                    val = menu_dict[key]
                    if isinstance(val, str):
                        # Final executable task
                        subprocess.run(val, shell=True)
                        Display.deinit_display()
                        sys.exit(0)
                    else:
                        # Submenu
                        result = navigate_menu(val, key, is_root=False)
                        if result is not None:
                            return result
                        # else stay in current menu after backing out

        # --- Start navigation at root level ---
        navigate_menu(root, title, is_root=True)