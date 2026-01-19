

from datetime import datetime
import os
from zoneinfo import ZoneInfo
from controller.controller_inputs import ControllerInput
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class TimezoneMenu():
    def __init__(self):
        pass

    def list_timezone_files(self,timezone_dir, verify_via_datetime):
        PyUiLogger.get_logger().info(f"Scanning {timezone_dir} for timezones")
        potential_timezone_entries = []

        # Iterate over each subdirectory in the base directory
        for subfolder in os.listdir(timezone_dir):
            subfolder_path = os.path.join(timezone_dir, subfolder)

            # Make sure it's a directory
            if os.path.isdir(subfolder_path):
                PyUiLogger.get_logger().info(f"Checking subfolder {subfolder} for timezones")
                # List all files in the subfolder
                for filename in os.listdir(subfolder_path):
                    file_path = os.path.join(subfolder_path, filename)
                    
                    # Only include if it's a regular file
                    if os.path.isfile(file_path):
                        potential_timezone_entries.append(f"{subfolder}/{filename}")

        for filename in os.listdir(timezone_dir):
            file_path = os.path.join(subfolder_path, filename)
            if os.path.isfile(file_path):
                potential_timezone_entries.append(f"{filename}")

        timezone_entries = []
        for entry in potential_timezone_entries:
            try:
                if(verify_via_datetime):
                    datetime.now(ZoneInfo(entry))
                timezone_entries.append(entry)

            except Exception as e:
                # If timezone fails to load for any reason, skip it
                PyUiLogger.get_logger().warning(f"Failed to load timezone {entry}: {e}")

        return timezone_entries


    def ask_user_for_timezone(self,timezone_entries):
        selected = Selection(None,None,0)
        options = []
        for timezone in timezone_entries:
            try:
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
                PyUiLogger.get_logger().warning(f"Failed to load timezone {timezone}: {e}")

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