from collections import defaultdict
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import List

from controller.controller_inputs import ControllerInput

from display.display import Display
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType

class OptionSelectUI:

    @staticmethod
    def _build_tree_from_flat_map(flat_map):
        """
        Convert a flat dict with slash-separated keys into a nested dict-of-dicts.
        Leaves (final parts) contain the original string value.
        """
        def tree():
            return defaultdict(tree)
        root = tree()

        for key, value in flat_map.items():
            if key == "descriptions":
                continue
            parts = key.split("/")
            node = root
            for part in parts[:-1]:
                node = node[part]
            node[parts[-1]] = value  # leaf = original path/string
        return root

    @staticmethod
    def _write_result_to_file(result):
        """Write selection result to selection.txt next to package root (two levels up)."""
        script_dir = Path(__file__).resolve().parent.parent
        result_file = script_dir / "selection.txt"
        PyUiLogger.get_logger().info(f"Writing {result} to {result_file}")
        try:
            with result_file.open("w", encoding="utf-8") as f:
                f.write(result)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error writing result to file: {e}")

    @staticmethod
    def _make_option_list_from_menu(menu_dict, folder, is_root, exit_after_running, view_type, execute_immediately=False, descriptions=None):
        if descriptions is None:
            descriptions = {}

        def run_action(val):
            if exit_after_running:
                Display.deinit_display()
                subprocess.run(val, shell=True)
                sys.exit(0)
            elif execute_immediately:
                Display.display_message(f"Executing: {val}")
                subprocess.run(val, shell=True)
                Display.display_message(f"Finished Running {val}", duration_ms=2000)
            else:
                OptionSelectUI._write_result_to_file(val)
                return val

        option_list = []

        if isinstance(menu_dict, dict):
            for key, val in menu_dict.items():
                img_path = f"{folder}/Imgs/{key}.png"
                if not os.path.exists(img_path):
                    img_path = f"{folder}/Imgs/{key}.qoi"

                # Look up description from top-level dictionary
                desc_text = descriptions.get(key)
                if is_root:
                    if isinstance(val, str):
                        # leaf node
                        option_value = lambda _ignored_controller_input=None, v=val: run_action(v)
                    else:
                        # submenu node
                        option_value = lambda _ignored_controller_input=None, v=val, k=key: OptionSelectUI.navigate_menu(
                            menu_dict=v,
                            title=k,
                            folder=folder,
                            exit_after_running=exit_after_running,
                            view_type=view_type,
                            execute_immediately=execute_immediately,
                            is_root=False,
                            descriptions=descriptions
                        )
                else:
                    # navigation mode just store key for lookup
                    option_value = key

                option_list.append(
                    GridOrListEntry(
                        primary_text=key,
                        value=option_value,
                        image_path=img_path,
                        description=desc_text
                    )
                )

        return option_list

    @staticmethod
    def navigate_menu(menu_dict, title, folder, exit_after_running, view_type, execute_immediately=False, is_root=False, descriptions=None):
        """
        Core navigation function.
        - If is_root is True: returns a list of GridOrListEntry with .value as callable.
        - If is_root is False: displays the menu and handles navigation.
        """
        if descriptions is None:
            descriptions = {}

        # If menu_dict is a string (leaf), just execute
        if isinstance(menu_dict, str):
            return OptionSelectUI._make_option_list_from_menu(
                {menu_dict: menu_dict},
                folder,
                is_root=True,
                exit_after_running=exit_after_running,
                view_type=view_type,
                execute_immediately=execute_immediately,
                descriptions=descriptions
            )

        # Build option list
        option_list = OptionSelectUI._make_option_list_from_menu(
            menu_dict,
            folder,
            is_root,
            exit_after_running,
            view_type,
            execute_immediately=execute_immediately,
            descriptions=descriptions
        )

        if is_root:
            return option_list

        # UI navigation mode
        selected = Selection(None, None, 0)
        view = ViewCreator.create_view(
            view_type=view_type,
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
                return None
            elif inp == ControllerInput.A:
                key = entry.get_value()
                val = menu_dict[key]

                if isinstance(val, str):
                    if exit_after_running:
                        Display.deinit_display()
                        subprocess.run(val, shell=True)
                        sys.exit(0)
                    elif execute_immediately:
                        Display.display_message(f"Executing: {val}")
                        subprocess.run(val, shell=True)
                        Display.display_message(f"Finished Running {val}", duration_ms=1000)
                    else:
                        OptionSelectUI._write_result_to_file(val)
                        return val
                else:
                    result = OptionSelectUI.navigate_menu(
                        val,
                        key,
                        folder,
                        exit_after_running,
                        view_type=view_type,
                        execute_immediately=execute_immediately,
                        is_root=False,
                        descriptions=descriptions
                    )
                    if result is not None:
                        return result

    @staticmethod
    def get_top_level_options_from_json(json_path: str | Path, view_type, exit_after_running=False, execute_immediately=False) -> List[GridOrListEntry]:
        """
        Reads JSON, returns top-level GridOrListEntry list with .value lambdas.
        """
        json_path = Path(json_path)
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        descriptions = data.get("descriptions", {})
        root_dict = OptionSelectUI._build_tree_from_flat_map(data)
        folder = str(json_path.parent)

        return OptionSelectUI.navigate_menu(
            root_dict,
            title="",
            folder=folder,
            exit_after_running=exit_after_running,
            view_type=view_type,
            execute_immediately=execute_immediately,
            is_root=True,
            descriptions=descriptions
        )

    @staticmethod
    def display_menu_ui(title, menu_dict, folder, exit_after_running, view_type):
        """
        Show menu starting from menu_dict.
        """
        return OptionSelectUI.navigate_menu(
            menu_dict,
            title,
            folder,
            exit_after_running,
            view_type=view_type,
            is_root=False
        )

    @staticmethod
    def display_option_list(title, input_json, exit_after_running):
        """
        Convenience function to preserve legacy API.
        """
        with open(input_json, "r", encoding="utf-8") as f:
            data = json.load(f)

        descriptions = data.get("descriptions", {})
        root_dict = OptionSelectUI._build_tree_from_flat_map(data)
        folder = str(Path(input_json).parent)

        result = OptionSelectUI.display_menu_ui(
            title,
            root_dict,
            folder,
            exit_after_running=exit_after_running,
            view_type=ViewType.TEXT_AND_IMAGE
        )

        if result is None:
            OptionSelectUI._write_result_to_file("EXIT")
            result = "EXIT"

        return result
