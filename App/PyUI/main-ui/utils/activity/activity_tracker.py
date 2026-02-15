


from typing import Dict
from controller.controller_inputs import ControllerInput
from devices.device import Device
from utils.activity.activity_log import ActivityLog
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType


class ActivityTracker:
    def __init__(self):
        self.activity_log = []

    def run_activity_tracking_app(self):
        activity_log = ActivityLog(PyUiConfig.get_activity_log_path())

        option_list = []
        option_list.append(
            GridOrListEntry(
                primary_text="Game Tracking",
                value=lambda input_value,activity_list=activity_log,
                : self.all_apps_list(activity_list)
            )
        )
        option_list.append(
            GridOrListEntry(
                primary_text="System Tracking",
                value=lambda input_value,activity_list=activity_log,
                : self.by_system_list(activity_list)
            )
        )

        

        view = ViewCreator.create_view(
                view_type=ViewType.ICON_AND_DESC,
                top_bar_text="Activity Tracker", 
                options=option_list,
                selected_index=0)

        accepted_inputs = [ControllerInput.A, ControllerInput.B]

        while (True):
            selected = view.get_selection(accepted_inputs)
            if(selected is not None):
                if (ControllerInput.B == selected.get_input()):
                    return
                elif(ControllerInput.A == selected.get_input()):
                    selected.get_selection().get_value()(selected.get_input())

    def all_apps_list(self, activity_log : ActivityLog):
        
        option_list = []
        option_list.append(
            GridOrListEntry(
                primary_text="Today",
                value=lambda input_value,activity_list=activity_log.all_apps_today(),
                : self.display_activity_details(activity_list)
            )
        )
        option_list.append(
            GridOrListEntry(
                primary_text="This Week",
                value=lambda input_value,activity_list=activity_log.all_apps_this_week(),
                : self.display_activity_details(activity_list)
            )
        )
        option_list.append(
            GridOrListEntry(
                primary_text="This Month",
                value=lambda input_value,activity_list=activity_log.all_apps_this_month(),
                : self.display_activity_details(activity_list)
            )
        )  
        option_list.append(
            GridOrListEntry(
                primary_text="This Year",
                value=lambda input_value,activity_list=activity_log.all_apps_this_year(),
                : self.display_activity_details(activity_list)
            )
        ) 
        option_list.append(
            GridOrListEntry(
                primary_text="All Time",
                value=lambda input_value,activity_list=activity_log.all_apps_all_time(),
                : self.display_activity_details(activity_list)
            )
        )  
        view = ViewCreator.create_view(
                view_type=ViewType.ICON_AND_DESC,
                top_bar_text="Activity Tracker", 
                options=option_list,
                selected_index=0)

        accepted_inputs = [ControllerInput.A, ControllerInput.B]

        while (True):
            selected = view.get_selection(accepted_inputs)
            if(selected is not None):
                if (ControllerInput.B == selected.get_input()):
                    return
                elif(ControllerInput.A == selected.get_input()):
                    selected.get_selection().get_value()(selected.get_input())

    def by_system_list(self, activity_log : ActivityLog):
        option_list = []       
        option_list.append(
            GridOrListEntry(
                primary_text="Today",
                value=lambda input_value,activity_list=activity_log.systems_today(),
                : self.display_activity_details(activity_list)
            )
        )  
        option_list.append(
            GridOrListEntry(
                primary_text="This Week",
                value=lambda input_value,activity_list=activity_log.systems_this_week(),
                : self.display_activity_details(activity_list)
            )
        )  
        option_list.append(
            GridOrListEntry(
                primary_text="This Month",
                value=lambda input_value,activity_list=activity_log.systems_this_month(),
                : self.display_activity_details(activity_list)
            )
        )          
        option_list.append(
            GridOrListEntry(
                primary_text="This Year",
                value=lambda input_value,activity_list=activity_log.systems_this_year(),
                : self.display_activity_details(activity_list)
            )
        )  
        option_list.append(
            GridOrListEntry(
                primary_text="All Time",
                value=lambda input_value,activity_list=activity_log.systems_all_time(),
                : self.display_activity_details(activity_list)
            )
        )        

        view = ViewCreator.create_view(
                view_type=ViewType.ICON_AND_DESC,
                top_bar_text="System Activity Tracker", 
                options=option_list,
                selected_index=0)

        accepted_inputs = [ControllerInput.A, ControllerInput.B]

        while (True):
            selected = view.get_selection(accepted_inputs)
            if(selected is not None):
                if (ControllerInput.B == selected.get_input()):
                    return
                elif(ControllerInput.A == selected.get_input()):
                    selected.get_selection().get_value()(selected.get_input())


    def display_activity_details(self, activity_list: Dict[str, int]):
        option_list = []
        for app, total_seconds in activity_list.items():
            if(app != "PyUI"):
                img = Device.get_device().get_image_for_activity(app)
                hours = total_seconds // 3600
                minutes = (total_seconds % 3600) // 60
                time_str = f"{hours}h {minutes}m" if hours > 0 else f"{minutes}m"
                if app.endswith("launch.sh"):
                    primary = app.rsplit("/", 2)[-2]   # directory before launch.sh
                else:
                    primary = app.rsplit("/", 1)[-1].rsplit(".", 1)[0]
                option_list.append(
                    GridOrListEntry(
                        primary_text=primary,
                        value_text=time_str,
                        icon=img
                    )
                )

        view = ViewCreator.create_view(
                view_type=ViewType.ICON_AND_DESC,
                top_bar_text="Activity Tracker", 
                options=option_list,
                selected_index=0)

        accepted_inputs = [ControllerInput.B]

        while (True):
            selected = view.get_selection(accepted_inputs)
            if (ControllerInput.B == selected.get_input()):
                return
