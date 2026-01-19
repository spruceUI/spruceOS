

import os
import sys
from controller.controller_inputs import ControllerInput
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class LanguageMenu():
    def __init__(self):
        pass

    def list_languages(self):
        base_dir = os.path.abspath(sys.path[0])
        parent_dir = os.path.dirname(base_dir)
        lang_dir = os.path.join(parent_dir, "lang")

        language_entries = []

        for filename in os.listdir(lang_dir):
            language_entries.append(os.path.splitext(os.path.basename(filename))[0])

        return language_entries


    def ask_user_for_language(self):
        selected = Selection(None,None,0)
        options = []
        for language in self.list_languages():
            try:
                options.append(
                    GridOrListEntry(
                        primary_text=language,
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=language
                    )
                )
            except Exception as e:
                # If timezone fails to load for any reason, skip it
                PyUiLogger.get_logger().warning(f"Failed to load language {language}: {e}")

        view = ViewCreator.create_view(
            view_type=ViewType.ICON_AND_DESC,
            top_bar_text="Language", 
            options=options, 
            selected_index=selected.get_index(),
        )

        while(True):
            selected = view.get_selection()
            if(ControllerInput.A == selected.get_input()):
                return selected.get_selection().get_value()
            elif(ControllerInput.B == selected.get_input()):
                return None