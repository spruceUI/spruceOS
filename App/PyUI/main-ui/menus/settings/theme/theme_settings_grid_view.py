
from controller.controller_inputs import ControllerInput
from display.display import Display
from display.font_purpose import FontPurpose
from menus.settings.theme.theme_settings_menu_common import ThemeSettingsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry


class ThemeSettingsGridView(ThemeSettingsMenuCommon):
    def __init__(self):
        super().__init__()

    def build_options_list(self) -> list[GridOrListEntry]:
        option_list = []
        option_list.append(
            self.build_numeric_entry(
                primary_text="Sel BG Resize Pad Width",
                get_value_func=Theme.get_grid_multi_row_sel_bg_resize_pad_width,
                set_value_func=Theme.set_grid_multi_row_sel_bg_resize_pad_width
            )
        )
        option_list.append(
            self.build_numeric_entry(
                primary_text="Sel BG Resize Pad Height",
                get_value_func=Theme.get_grid_multi_row_sel_bg_resize_pad_height,
                set_value_func=Theme.set_grid_multi_row_sel_bg_resize_pad_height
            )
        )

        return option_list
