

from apps.app_config import AppConfig
from controller.controller_inputs import ControllerInput
from menus.app.hidden_apps_manager import AppsManager
from themes.theme import Theme
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType


from menus.language.language import Language

class AppMenuPopup:
    def __init__(self, current_show_all_apps_setting):
        self.current_show_all_apps_setting = current_show_all_apps_setting

    def toggle_hiding_app(self, app : AppConfig, input_value):
        if(ControllerInput.A == input_value):
            if AppsManager.is_hidden(app):
                AppsManager.show_app(app)
            else:
                AppsManager.hide_app(app)

    def toggle_show_all_apps(self, input_value):
        if(ControllerInput.A == input_value):
            self.current_show_all_apps_setting = not self.current_show_all_apps_setting

    def run_app_menu_popup(self, app: AppConfig):
        popup_options = []

        if(app):
            popup_options.append(GridOrListEntry(
                    primary_text=Language.show_app() if AppsManager.is_hidden(app) else "Hide App",
                    image_path=Theme.settings(),
                    image_path_selected=Theme.settings_selected(),
                    description="",
                    icon=None,
                    value=lambda input_value, app=app: self.toggle_hiding_app(app, input_value)
            ))

        popup_options.append(GridOrListEntry(
                primary_text=Language.hide_hidden_apps() if self.current_show_all_apps_setting else "Show Hidden Apps",
                image_path=Theme.settings(),
                image_path_selected=Theme.settings_selected(),
                description="",
                icon=None,
                value=lambda input_value: self.toggle_show_all_apps(input_value)
        ))

        top_bar_text = "App Options"
        if(app):
            top_bar_text = f"{app.get_label()} Sub Options"
        popup_view = ViewCreator.create_view(
            view_type=ViewType.POPUP,
            options=popup_options,
            top_bar_text=top_bar_text,
            selected_index=0,
            cols=Theme.popup_menu_cols(),
            rows=Theme.popup_menu_rows())

        while (popup_selection := popup_view.get_selection()):
            if(popup_selection.get_input() is not None):
                PyUiLogger.get_logger().info(f"Received {popup_selection.get_input()}")
                break
        
        if(popup_selection.get_input() is not None):
            popup_view.view_finished()

        if(ControllerInput.A == popup_selection.get_input()): 
            popup_selection.get_selection().get_value()(popup_selection.get_input())
        
        return self.current_show_all_apps_setting