

import os
from controller.controller import Controller
from devices.device import Device
from display.display import Display
from themes.theme import Theme
from views.descriptive_list_view import DescriptiveListView
from views.grid_or_list_entry import GridOrListEntry


class AppMenu:
    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme):
        self.display : Display= display
        self.controller : Controller = controller
        self.device : Device= device
        self.theme : Theme= theme
        self.appFinder = device.get_app_finder()

    def _convert_to_theme_version_of_icon(self, icon_path):
        return os.path.join(self.theme.path,"icons","app",os.path.basename(icon_path))

    def run_app_selection(self) :
        selected = "new"
        app_list = []
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

        options_list = DescriptiveListView(self.display,self.controller,self.device,self.theme, "Apps", app_list, self.theme.get_list_large_selected_bg())
        while((selected := options_list.get_selection()) is not None):
            self.device.run_app([selected.get_selection().get_value()])
            self.controller.clear_input_queue()
            self.display.reinitialize()
