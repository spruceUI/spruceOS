

import os
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from menus.app.app_menu_popup import AppMenuPopup
from menus.app.hidden_apps_manager import AppsManager
from menus.language.language import Language
from themes.theme import Theme
from utils.py_ui_state import PyUiState
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator


class AppMenu:
    def __init__(self):
        self.appFinder = Device.get_app_finder()
        self.show_all_apps = False

    def _convert_to_theme_version_of_icon(self, icon_path):
        return Theme.get_app_icon(os.path.basename(icon_path))

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
        if(icon_path_from_config is not None):
            icon_priority.append(self._convert_to_theme_version_of_icon(icon_path_from_config))
            icon_priority.append(icon_path_from_config)
            icon_priority.append(os.path.join(app_folder,icon_path_from_config))
        icon_priority.append(os.path.join(app_folder,"icon.png"))
        return self.get_first_existing_path(icon_priority)
    
    def save_app_selection(self, selected):
        filepath = selected.get_selection().get_value().get_launch()
        directory = selected.get_selection().get_value().get_folder()
        PyUiState.set_last_app_selection(directory,filepath)

    def run_app_selection(self) :
        running = True

        while(running):
            last_selected_dir, last_selected_file = PyUiState.get_last_app_selection()
            selected = Selection(None,None,0)
            app_list = []
            view = None
            idx = 0
            device_apps = self.appFinder.get_apps()
            device_apps.sort(key=lambda app: app.get_label() or "")
            for app in device_apps:
                hidden = AppsManager.is_hidden(app) and not self.show_all_apps
                devices = app.get_devices()
                supported_device = not devices or Device.get_device_name() in devices
                if(app.get_label() is not None and not hidden and supported_device):
                    icon = self.get_icon(app.get_folder(),app.get_icon())
                    app_list.append(
                        GridOrListEntry(
                            primary_text=app.get_label() + "(Hidden)" if AppsManager.is_hidden(app) else app.get_label(),
                            image_path=icon,
                            image_path_selected=icon,
                            description=app.get_description(),
                            icon=icon,
                            value=app
                        )
                    )
                    if(app.get_folder() == last_selected_dir and app.get_launch() == last_selected_file):
                        selected = Selection(None,None,idx)
                    idx +=1

            if(view is None):
                view = ViewCreator.create_view(
                    view_type=Theme.get_view_type_for_app_menu(),
                    top_bar_text=Language.apps(), 
                    options=app_list,
                    selected_index=selected.get_index())
            else:
                view.set_options(app_list)
            
            selected = Selection(None, None, None)
            while(selected.get_input() is None):
                selected = view.get_selection(select_controller_inputs = [ControllerInput.A, ControllerInput.MENU])
                if(ControllerInput.A == selected.get_input()):
                    self.save_app_selection(selected)
                    launch = selected.get_selection().get_value().get_launch()
                    folder = selected.get_selection().get_value().get_folder()
                    Display.deinit_display()
                    Device.run_app(folder,launch)
                    Controller.clear_input_queue()
                    Display.reinitialize()
                elif(ControllerInput.B == selected.get_input()):
                    self.save_app_selection(selected)
                    if(not Theme.skip_main_menu()):
                        running = False
                elif(ControllerInput.MENU == selected.get_input()):
                    self.save_app_selection(selected)
                    self.show_all_apps = AppMenuPopup(self.show_all_apps).run_app_menu_popup(selected.get_selection().get_value())
                elif(Theme.skip_main_menu() and ControllerInput.L1 == selected.get_input()):
                    self.save_app_selection(selected)
                    self.save_app_selection(selected)
                    return ControllerInput.L1
                elif(Theme.skip_main_menu() and ControllerInput.R1 == selected.get_input()):
                    self.save_app_selection(selected)
                    self.save_app_selection(selected)
                    return ControllerInput.R1
                
