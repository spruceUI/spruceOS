

import os
from apps.pyui_app import PyUiAppConfig
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from menus.app.app_menu_popup import AppMenuPopup
from menus.app.hidden_apps_manager import AppsManager
from menus.language.language import Language
from themes.theme import Theme
from utils.boxart.box_art_scraper import BoxArtScraper
from utils.logger import PyUiLogger
from utils.py_ui_state import PyUiState
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator


class AppMenu:
    def __init__(self):
        self.appFinder = Device.get_device().get_app_finder()
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
            if(app_folder is not None):
                icon_priority.append(os.path.join(app_folder,icon_path_from_config))
        if(app_folder is not None):
            icon_priority.append(os.path.join(app_folder,"icon.png"))
        return self.get_first_existing_path(icon_priority)
    
    def save_app_selection(self, selected):
        if(selected.get_selection() is not None):
            PyUiState.set_last_app_selection(selected.get_selection().get_extra_data().get_label())

    def handle_app_selection(self, app):
        launch = app.get_launch()
        folder = app.get_folder()
        Display.deinit_display()
        Device.get_device().run_app(folder,launch)
        Controller.clear_input_queue()
        Display.reinitialize()
        
    def append_pyui_apps(self, app_list):
        system_config = Device.get_device().get_system_config()
        if(not system_config.simple_mode_enabled()):
            boxart_scraper_config = PyUiAppConfig("Boxart Scraper")
            hidden = AppsManager.is_hidden(boxart_scraper_config) and not self.show_all_apps
            if(not hidden):
                icon = self.get_icon(None,"scraper.png")
                if(icon is None):
                    icon = Theme.get_cfw_default_icon("scraper.png")
                app_list.append(
                        GridOrListEntry(
                            primary_text=boxart_scraper_config.get_label() + "(Hidden)" if AppsManager.is_hidden(boxart_scraper_config) else boxart_scraper_config.get_label(),
                            image_path=None,
                            image_path_selected=None,
                            description="Scrape game boxart",
                            icon=icon,
                            extra_data=boxart_scraper_config,
                            value=BoxArtScraper().scrape_boxart
                        )
                )
                
    def run_app_selection(self) :
        running = True
    
        system_config = Device.get_device().get_system_config()

        while(running):
            last_selected_label = PyUiState.get_last_app_selection()
            selected = Selection(None,None,0)
            app_list = []
            view = None
            device_apps = self.appFinder.get_apps()
            for app in device_apps:
                hidden = AppsManager.is_hidden(app) and not self.show_all_apps
                devices = app.get_devices()
                supported_device = not devices or Device.get_device().get_device_name() in devices
                allowed_in_mode = not system_config.simple_mode_enabled() or not app.get_hide_in_simple_mode()
                if(allowed_in_mode and app.get_label() is not None and not hidden and supported_device):
                    icon = self.get_icon(app.get_folder(),app.get_icon())
                    app_list.append(
                        GridOrListEntry(
                            primary_text=app.get_label() + "(Hidden)" if AppsManager.is_hidden(app) else app.get_label(),
                            image_path=icon,
                            image_path_selected=icon,
                            description=app.get_description(),
                            icon=icon,
                            extra_data=app,
                            value=lambda app=app: self.handle_app_selection(app)
                        )
                    )


            self.append_pyui_apps(app_list)
            app_list.sort(key=lambda app: app.get_primary_text() or "")

            idx = 0
            for app in app_list:
                if(app.get_primary_text() == last_selected_label):
                    selected = Selection(None,None,idx)
                    break
                idx += 1

            PyUiLogger.get_logger().info(f"Finish app list building")

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
                    selected.get_selection().get_value()()
                elif(ControllerInput.B == selected.get_input()):
                    self.save_app_selection(selected)
                    running = False
                elif(ControllerInput.MENU == selected.get_input()):
                    self.save_app_selection(selected)
                    if(selected.get_selection()):
                        self.show_all_apps = AppMenuPopup(self.show_all_apps).run_app_menu_popup(selected.get_selection().get_extra_data())
                    else:
                        self.show_all_apps = AppMenuPopup(self.show_all_apps).run_app_menu_popup(None)
                elif(Theme.skip_main_menu() and ControllerInput.L1 == selected.get_input()):
                    self.save_app_selection(selected)
                    return ControllerInput.L1
                elif(Theme.skip_main_menu() and ControllerInput.R1 == selected.get_input()):
                    self.save_app_selection(selected)
                    return ControllerInput.R1
                        
                    
