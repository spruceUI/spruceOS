

import os
from controller.controller import Controller
from devices.device import Device
from display.display import Display
from themes.theme import Theme
from views.descriptive_list_view import DescriptiveListView
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class AppMenu:
    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme):
        self.display : Display= display
        self.controller : Controller = controller
        self.device : Device= device
        self.theme : Theme= theme
        self.appFinder = device.get_app_finder()
        self.view_creator = ViewCreator(display,controller,device,theme)

    def _convert_to_theme_version_of_icon(self, icon_path):
        return os.path.join(self.theme.path,"icons","app",os.path.basename(icon_path))

    def run_app_selection(self) :
        selected = Selection(None,None,0)
        app_list = []
        view = None
        for app in self.appFinder.get_apps():
            if(app.get_label() is not None):
                app_list.append(
                    GridOrListEntry(
                        primary_text=app.get_label(),
                        image_path=app.get_icon(),
                        image_path_selected=app.get_icon(),
                        description=app.get_description(),
                        icon=self._convert_to_theme_version_of_icon(app.get_icon()),
                        value=app.get_launch()
                    )
                )
        if(view is None):
            view = self.view_creator.create_view(
                view_type=self.theme.get_view_type_for_app_menu(),
                top_bar_text="Apps", 
                options=app_list,
                selected_index=selected.get_index())
        else:
            view.set_options(app_list)
        
        while((selected := view.get_selection()) is not None):
            filepath = selected.get_selection().get_value()
            directory = os.path.dirname(filepath)
            self.display.deinit_display()
            self.device.run_app([filepath], directory)
            self.controller.clear_input_queue()
            self.display.reinitialize()
