
from controller.controller_inputs import ControllerInput
from display.display import Display
from display.font_purpose import FontPurpose
from menus.settings.theme.theme_settings_menu_common import ThemeSettingsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry


class ThemeSettingsTopBar(ThemeSettingsMenuCommon):
    def __init__(self):
        super().__init__()

    def selection_made(self):
        Display.clear_text_cache()

    def build_options_list(self) -> list[GridOrListEntry]:
        option_list = []

        option_list.append(
            self.build_numeric_entry(
                primary_text="Left Side Initial X Offset",
                get_value_func=Theme.get_top_bar_initial_x_offset,
                set_value_func=Theme.set_top_bar_initial_x_offset
            )
        )
                
        return option_list
