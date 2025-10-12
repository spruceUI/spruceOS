from controller.controller_inputs import ControllerInput
from display.display import Display
from utils.logger import PyUiLogger
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType
from abc import ABC, abstractmethod


class SettingsMenu(ABC):
    def __init__(self):
        pass

    @abstractmethod
    def build_options_list(self):
        pass

    def show_menu(self) :
        selected = Selection(None, None, 0)
        list_view = None
        self.theme_changed = False
        self.theme_ever_changed = False
        while(selected is not None):
            option_list = self.build_options_list()
            
            if(self.theme_changed):
                self.theme_ever_changed = True

            if(list_view is None or self.theme_changed):
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
            elif(ControllerInput.B == selected.get_input()):
                selected = None
        
        return self.theme_ever_changed

    def get_next_entry(self,current_entry, all_entries, direction):
        if current_entry not in all_entries:
            PyUiLogger.get_logger().info(f"Current entry {current_entry} is invalid.")
            return all_entries[0]

        current_index = all_entries.index(current_entry)
        next_index = (current_index + direction) % len(all_entries)
        return all_entries[next_index]

