

from abc import abstractmethod
from controller.controller_inputs import ControllerInput
from menus.settings.settings_menu import SettingsMenu
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class ThemeSettingsMenuCommon(SettingsMenu):
    def __init__(self):
        pass

    @abstractmethod
    def build_options_list(self) -> list[GridOrListEntry]:
        pass

    def selection_made(self):
        pass

    def show_theme_options_menu(self):
        selected = Selection(None, None, 0)
        list_view = None
        self.theme_changed = False
        reload_view = True
        while(selected is not None):
            option_list = self.build_options_list()
            

            if(reload_view):
                reload_view = False
                list_view = ViewCreator.create_view(
                    view_type=ViewType.ICON_AND_DESC,
                    top_bar_text="Settings", 
                    options=option_list,
                    selected_index=selected.get_index())
                self.theme_changed = False
            else:
                list_view.set_options(option_list)

            control_options = [ControllerInput.A, ControllerInput.DPAD_LEFT, ControllerInput.DPAD_RIGHT,
                                                  ControllerInput.L1, ControllerInput.R1]
            selected = list_view.get_selection(control_options)

            if(selected.get_input() in control_options):
                selected.get_selection().get_value()(selected.get_input())
                self.selection_made()
                reload_view = True
            elif(ControllerInput.B == selected.get_input()):
                selected = None
