

from datetime import datetime
import os
import zoneinfo
from zoneinfo import ZoneInfo
from controller.controller_inputs import ControllerInput
from utils.logger import PyUiLogger
from menus.language.language import Language
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

        # ZoneInfo resolves names against its own search path, not against the
        # directory being listed, and that path defaults to /usr/share/zoneinfo
        # and friends. Without this every entry fails to verify on any device
        # whose zones live somewhere else, and the menu comes up empty.
        if verify_via_datetime:
            zoneinfo.reset_tzpath(to=[timezone_dir])

        # Walk the whole tree rather than the top two levels. Zones sit at three
        # different depths: UTC at the top, America/New_York one down, and
        # America/Argentina/Buenos_Aires two down. Scanning only one level below
        # the root, which is what this did before, silently dropped every zone
        # in Argentina, Indiana, Kentucky and North Dakota.
        for dirpath, _, filenames in os.walk(timezone_dir):
            for filename in filenames:
                file_path = os.path.join(dirpath, filename)
                if os.path.isfile(file_path):
                    potential_timezone_entries.append(
                        os.path.relpath(file_path, timezone_dir))

        timezone_entries = []
        for entry in potential_timezone_entries:
            try:
                if(verify_via_datetime):
                    datetime.now(ZoneInfo(entry))
                timezone_entries.append(entry)

            except Exception as e:
                # If timezone fails to load for any reason, skip it
                PyUiLogger.get_logger().warning(f"Failed to load timezone {entry}: {e}")

        # os.listdir hands these back in whatever order the filesystem holds
        # them, which is unusable in a list this long.
        timezone_entries.sort()
        PyUiLogger.get_logger().info(f"Found {len(timezone_entries)} timezones in {timezone_dir}")
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
            top_bar_text=Language.set_timezone(), 
            options=options, 
            selected_index=selected.get_index(),
        )

        while(True):
            selected = view.get_selection()
            if(ControllerInput.A == selected.get_input()):
                return selected.get_selection().get_value()
            elif(ControllerInput.B == selected.get_input()):
                return None