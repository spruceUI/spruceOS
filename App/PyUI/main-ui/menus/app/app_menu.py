

import os
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator


class AppMenu:
    def __init__(self):
        self.appFinder = Device.get_app_finder()

    def _convert_to_theme_version_of_icon(self, icon_path):
        return os.path.join(Theme.get_theme_path(),"icons","app",os.path.basename(icon_path))

    def get_first_existing_path(self,file_priority_list):
        for path in file_priority_list:
            try:
                if path and os.path.isfile(path):
                    return path
            except Exception:
                pass
        return None 

    def get_icon(self, app_folder, icon_path_from_config):
        icon_priority = []
        icon_priority.append(os.path.join(Theme.get_theme_path(),"icons","app",os.path.basename(icon_path_from_config)))
        icon_priority.append(icon_path_from_config)
        icon_priority.append(os.path.join(app_folder,icon_path_from_config))
        icon_priority.append(os.path.join(app_folder,"icon.png"))
        return self.get_first_existing_path(icon_priority)

    def run_app_selection(self) :
        selected = Selection(None,None,0)
        app_list = []
        view = None
        for app in self.appFinder.get_apps():
            if(app.get_label() is not None):
                icon = self.get_icon(app.get_folder(),app.get_icon())
                print(f"Adding app: {app.get_label()} with icon: {icon}")
                app_list.append(
                    GridOrListEntry(
                        primary_text=app.get_label(),
                        image_path=icon,
                        image_path_selected=icon,
                        description=app.get_description(),
                        icon=icon,
                        value=app.get_launch()
                    )
                )
        if(view is None):
            view = ViewCreator.create_view(
                view_type=Theme.get_view_type_for_app_menu(),
                top_bar_text="Apps", 
                options=app_list,
                selected_index=selected.get_index())
        else:
            view.set_options(app_list)
        
        running = True
        while(running):
            selected = view.get_selection()
            if(ControllerInput.A == selected.get_input()):
                filepath = selected.get_selection().get_value()
                directory = os.path.dirname(filepath)
                Display.deinit_display()
                Device.run_app([filepath], directory)
                Controller.clear_input_queue()
                Display.reinitialize()
            elif(ControllerInput.B == selected.get_input()):
                running = False
