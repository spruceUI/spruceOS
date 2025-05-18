

from controller.controller_inputs import ControllerInput
from menus.settings.theme.theme_settings_game_select_menu import ThemeSettingsGameSelectMenu
from menus.settings.theme.theme_settings_main_menu import ThemeSettingsMainMenu
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType, get_next_view_type


class ThemeSettingsMenu():
    def __init__(self):
        pass

    def launch_main_menu_theme_options(self, input):
        if (input == ControllerInput.A):
            ThemeSettingsMainMenu().show_theme_options_menu()

    def launch_game_select_menu_theme_options(self, input):
        if (input == ControllerInput.A):
            ThemeSettingsGameSelectMenu().show_theme_options_menu()

    def build_options_list(self):
        option_list = []

        option_list.append(
            GridOrListEntry(
                primary_text="Main Menu Theme Options",
                value_text="",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.launch_main_menu_theme_options
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text="Game Select Menu Theme Options",
                value_text="",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.launch_game_select_menu_theme_options
            )
        )

        return option_list

    def show_theme_options_menu(self):
        selected = Selection(None, None, 0)
        list_view = None
        self.theme_changed = False
        while (selected is not None):
            option_list = self.build_options_list()

            if (list_view is None or self.theme_changed):
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

            if (selected.get_input() in control_options):
                selected.get_selection().get_value()(selected.get_input())
            elif (ControllerInput.B == selected.get_input()):
                selected = None
