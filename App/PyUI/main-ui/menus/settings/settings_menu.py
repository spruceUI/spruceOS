import sys
from controller.controller_inputs import ControllerInput
from display.display import Display
from utils.cfw_system_config import CfwSystemConfig
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType, get_next_view_type
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


    def change_indexed_array_option_for_menu_options_list(self, category, entry_name, input, all_options, current_value, update_value):
        try:
            selected_index = all_options.index(current_value)
        except:
            selected_index = 0
            PyUiLogger.get_logger().error(f"{current_value} not found in options for {entry_name}")

        PyUiLogger.get_logger().info(f"{current_value} is index {selected_index}")

        if(ControllerInput.DPAD_LEFT == input):
            selected_index-=1
            if(selected_index < 0):
                selected_index = len(all_options) -1
        elif(ControllerInput.DPAD_RIGHT == input):
            selected_index+=1
            if(selected_index == len(all_options)):
                selected_index = 0
        elif(ControllerInput.A == input):
            selected_index = self.get_selected_index(f"Select a {entry_name}", all_options)

        PyUiLogger.get_logger().info(f"{current_value} is updated to index {selected_index}")

        if(selected_index is not None):
            PyUiLogger.get_logger().info(f"Updating {entry_name} to {all_options[selected_index]}")
            update_value(category, entry_name, all_options[selected_index])

    def build_options_list_from_config_menu_options(self, category):
        option_list = []
        menu_options = CfwSystemConfig.get_menu_options(category=category)

        for name, option in menu_options.items():
            display_name = option.get('display')
            selected_value = CfwSystemConfig.get_selected_value(category,name)

            option_list.append(
                            GridOrListEntry(
                            primary_text=display_name,
                            value_text="<    " + selected_value + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=lambda 
                                input_value, 
                                entry_name=name, 
                                category=category,
                                all_options=option.get('options', []),
                                current_value=selected_value,update_value=CfwSystemConfig.set_menu_option
                                : self.change_indexed_array_option_for_menu_options_list(category, entry_name, input_value, all_options, current_value, update_value)
                    )
                )
        return option_list


    def build_enabled_disabled_entry(self, primary_text, get_value_func, set_value_func) -> GridOrListEntry:

        return GridOrListEntry(
            primary_text=primary_text,
            value_text="<    " + str(get_value_func()) + "    >",
            image_path=None,
            image_path_selected=None,
            description=None,
            icon=None,
            value=lambda input: self.change_enabled_disabled(
                input, get_value_func, set_value_func)
        )
    
    def build_numeric_entry(self, primary_text, get_value_func, set_value_func, min=1, max=sys.maxsize) -> GridOrListEntry:

        return GridOrListEntry(
            primary_text=primary_text,
            value_text="<    " + str(get_value_func()) + "    >",
            image_path=None,
            image_path_selected=None,
            description=None,
            icon=None,
            value=lambda input: self.change_numeric(
                input, get_value_func, set_value_func, min, max)
        )

    def build_percent_entry(self, primary_text, get_value_func, set_value_func) -> GridOrListEntry:

        return GridOrListEntry(
            primary_text=primary_text,
            value_text="<    " + str(get_value_func()) + "%    >",
            image_path=None,
            image_path_selected=None,
            description=None,
            icon=None,
            value=lambda input: self.change_numeric(
                input, get_value_func, set_value_func, min=0, max=100)
        )

    def build_view_type_entry(self, primary_text, get_value_func, set_value_func) -> GridOrListEntry:

        return GridOrListEntry(
            primary_text=primary_text,
            value_text="<    " + str(get_value_func().name) + "    >",
            image_path=None,
            image_path_selected=None,
            description=None,
            icon=None,
            value=lambda input: self.change_view_type(
                input, get_value_func, set_value_func)
        )
    
    
    def change_view_type(self, input, get_view_type_func, set_view_type_func):
        if input == ControllerInput.DPAD_LEFT:
            next_view_type = get_next_view_type(get_view_type_func(), -1)
        elif input == ControllerInput.DPAD_RIGHT:
            next_view_type = get_next_view_type(get_view_type_func(), +1)
        else:
            return  # No change for other inputs

        set_view_type_func(next_view_type)


    def build_enum_entry(self, primary_text, get_value_func, set_value_func, get_next_enum_type) -> GridOrListEntry:

        return GridOrListEntry(
            primary_text=primary_text,
            value_text="<    " + str(get_value_func().name) + "    >",
            image_path=None,
            image_path_selected=None,
            description=None,
            icon=None,
            value=lambda input: self.change_enum_type(
                input, get_value_func, set_value_func, get_next_enum_type)
        )
    
    def change_enum_type(self, input, get_value_func, set_value_func, get_next_enum_type):
        if input == ControllerInput.DPAD_LEFT:
            next_view_type = get_next_enum_type(get_value_func(), -1)
        elif input == ControllerInput.DPAD_RIGHT:
            next_view_type = get_next_enum_type(get_value_func(), +1)
        else:
            return  # No change for other inputs

        set_value_func(next_view_type)

    def change_enabled_disabled(self, input, get_value_func, set_value_func):
        value = get_value_func()

        if input == ControllerInput.DPAD_LEFT:
            value = not get_value_func()
        elif input == ControllerInput.DPAD_RIGHT:
            value = not get_value_func()
        else:
            return  # No change for other inputs

        set_value_func(value)

    def change_numeric(self, input, get_value_func, set_value_func, min=1, max=sys.maxsize):
        value = get_value_func()
        delta = 0
        if input == ControllerInput.DPAD_LEFT:
            delta = -1
        elif input == ControllerInput.DPAD_RIGHT:
            delta = +1
        elif input == ControllerInput.L1:
            delta = -10
        elif input == ControllerInput.R1:
            delta = +10
        else:
            return  # No change for other inputs

        value += delta
        if(min <= value <= max):
            set_value_func(value)
