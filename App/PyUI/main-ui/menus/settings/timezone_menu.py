

from datetime import datetime
import os
from zoneinfo import ZoneInfo
from controller.controller_inputs import ControllerInput
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class TimezoneMenu():
    def __init__(self):
        pass

    def list_timezone_files(self,base_dir = '/usr/share/zoneinfo'):
        timezone_entries = []

        # Iterate over each subdirectory in the base directory
        for subfolder in os.listdir(base_dir):
            subfolder_path = os.path.join(base_dir, subfolder)

            # Make sure it's a directory
            if os.path.isdir(subfolder_path):
                # List all files in the subfolder
                for filename in os.listdir(subfolder_path):
                    file_path = os.path.join(subfolder_path, filename)
                    
                    # Only include if it's a regular file
                    if os.path.isfile(file_path):
                        timezone_entries.append(f"{subfolder}/{filename}")

        return timezone_entries


    def ask_user_for_timezone(self):
        selected = Selection(None,None,0)
        options = []
        for timezone in self.list_timezone_files():
            try:
                now = datetime.now(ZoneInfo(timezone))
                options.append(
                    GridOrListEntry(
                        primary_text=timezone,
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=timezone
                    )
                )
            except Exception as e:
                # If timezone fails to load for any reason, skip it
                print(f"Failed to load timezone {timezone}: {e}")

        view = ViewCreator.create_view(
            view_type=ViewType.ICON_AND_DESC,
            top_bar_text="Timezone", 
            options=options, 
            selected_index=selected.get_index(),
        )

        while(True):
            selected = view.get_selection()
            if(ControllerInput.A == selected.get_input()):
                return selected.get_selection().get_value()
            elif(ControllerInput.B == selected.get_input()):
                return None