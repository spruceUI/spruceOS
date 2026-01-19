
from controller.controller_inputs import ControllerInput
from menus.settings import settings_menu
from menus.settings.list_of_options_selection_menu import ListOfOptionsSelectionMenu
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

GAME_SYSTEM_SORT_MODE_OPTIONS = ["Alphabetical","SortOrderKey","Custom"]

class GameSystemSelectSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()
    
    def change_game_system_sort_mode(self, input):
        if (ControllerInput.DPAD_LEFT == input):
            PyUiConfig.set_game_system_sort_mode(self.get_next_entry(PyUiConfig.game_system_sort_mode(),GAME_SYSTEM_SORT_MODE_OPTIONS,-1))
        elif (ControllerInput.DPAD_RIGHT == input):
            PyUiConfig.set_game_system_sort_mode(self.get_next_entry(PyUiConfig.game_system_sort_mode(),GAME_SYSTEM_SORT_MODE_OPTIONS,+1))
        elif (ControllerInput.A):
            selected_index = ListOfOptionsSelectionMenu().get_selected_option_index(GAME_SYSTEM_SORT_MODE_OPTIONS, "Game System Sort Mode")
            if(selected_index is not None):
                PyUiConfig.set_game_system_sort_mode(GAME_SYSTEM_SORT_MODE_OPTIONS[selected_index])

        self.theme_changed = True
        self.theme_ever_changed = True


    def change_priority(self, field, input):
        # Map field names to their getter and setter methods
        field_map = {
            "Type": {
                "get": PyUiConfig.game_system_sort_type_priority,
                "set": PyUiConfig.set_game_system_sort_type_priority
            },
            "Brand": {
                "get": PyUiConfig.game_system_sort_brand_priority,
                "set": PyUiConfig.set_game_system_sort_brand_priority
            },
            "Year": {
                "get": PyUiConfig.game_system_sort_year_priority,
                "set": PyUiConfig.set_game_system_sort_year_priority
            },
            "Name": {
                "get": PyUiConfig.game_system_sort_name_priority,
                "set": PyUiConfig.set_game_system_sort_name_priority
            }
        }

        # Get the current priorities in a list
        priorities = {
            "Type": field_map["Type"]["get"](),
            "Brand": field_map["Brand"]["get"](),
            "Year": field_map["Year"]["get"](),
            "Name": field_map["Name"]["get"]()
        }

        # Sort the fields by their current numeric priority
        ordered_fields = sorted(priorities.keys(), key=lambda k: priorities[k])

        # Find the current index of the selected field
        current_index = ordered_fields.index(field)

        # Handle circular swapping depending on input
        if input == ControllerInput.DPAD_LEFT:
            new_index = (current_index - 1) % len(ordered_fields)
        elif input == ControllerInput.DPAD_RIGHT:
            new_index = (current_index + 1) % len(ordered_fields)
        else:
            return  # ignore unrelated inputs

        # Swap the fields in the ordered list
        ordered_fields[current_index], ordered_fields[new_index] = \
            ordered_fields[new_index], ordered_fields[current_index]

        # Reassign numeric priorities (1, 2, 3) based on new order
        for i, key in enumerate(ordered_fields, start=1):
            field_map[key]["set"](i)

        self.theme_changed = True
        self.theme_ever_changed = True


    def change_show_all_game_systems(self, input):
        if (ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input or ControllerInput.A == input):
            PyUiConfig.set_show_all_game_systems(not PyUiConfig.show_all_game_systems())
            self.theme_changed = True
            self.theme_ever_changed = True

    def build_options_list(self):
        option_list = []

        option_list.append(
            GridOrListEntry(
                primary_text=Language.show_all_systems(),
                value_text="<    " +
                ("On" if PyUiConfig.show_all_game_systems() else "Off") + "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.change_show_all_game_systems
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text=Language.game_system_sorting(),
                value_text="<    " + PyUiConfig.game_system_sort_mode()+ "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.change_game_system_sort_mode
            )
        )

        if(PyUiConfig.game_system_sort_mode() == "Custom"):
            option_list.append(
                GridOrListEntry(
                    primary_text=Language.system_type_priority(),
                    value_text="<    " + str(PyUiConfig.game_system_sort_type_priority())+ "    >",
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value = lambda input=input, field="Type": self.change_priority(field,input)
                )
            )
            option_list.append(
                GridOrListEntry(
                    primary_text=Language.system_brand_priority(),
                    value_text="<    " + str(PyUiConfig.game_system_sort_brand_priority())+ "    >",
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value = lambda input=input, field="Brand": self.change_priority(field,input)
                )
            )
            option_list.append(
                GridOrListEntry(
                    primary_text=Language.system_year_priority(),
                    value_text="<    " + str(PyUiConfig.game_system_sort_year_priority())+ "    >",
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value = lambda input=input, field="Year": self.change_priority(field,input)
                )
            )
            option_list.append(
                GridOrListEntry(
                    primary_text=Language.system_name_priority(),
                    value_text="<    " + str(PyUiConfig.game_system_sort_name_priority())+ "    >",
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value = lambda input=input, field="Name": self.change_priority(field,input)
                )
            )

        return option_list
