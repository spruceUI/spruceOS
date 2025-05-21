

from abc import ABC, abstractmethod
from controller.controller_inputs import ControllerInput
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType, get_next_view_type


class ThemeSettingsMenuCommon(ABC):
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
    
    def build_numeric_entry(self, primary_text, get_value_func, set_value_func) -> GridOrListEntry:

        return GridOrListEntry(
            primary_text=primary_text,
            value_text="<    " + str(get_value_func()) + "    >",
            image_path=None,
            image_path_selected=None,
            description=None,
            icon=None,
            value=lambda input: self.change_numeric(
                input, get_value_func, set_value_func)
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

    def change_numeric(self, input, get_value_func, set_value_func):
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
        if(value > 0):
            set_value_func(value)
