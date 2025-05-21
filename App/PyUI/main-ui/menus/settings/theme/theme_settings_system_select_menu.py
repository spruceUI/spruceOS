
from controller.controller_inputs import ControllerInput
from menus.settings.theme.theme_settings_menu_common import ThemeSettingsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.view_type import ViewType


class ThemeSettingsSystemSelectMenu(ThemeSettingsMenuCommon):
    def __init__(self):
        super().__init__()

    def build_options_list(self) -> list[GridOrListEntry]:
        option_list = []
        option_list.append(
            self.build_view_type_entry("View Type", 
                                     Theme.get_view_type_for_system_select_menu, 
                                     Theme.set_view_type_for_system_select_menu)
        )

        if(ViewType.GRID == Theme.get_view_type_for_system_select_menu()):
            option_list.append(
                self.build_numeric_entry("Columns", 
                                        Theme.get_game_system_select_col_count, 
                                        Theme.set_game_system_select_col_count)
            )
            option_list.append(
                self.build_numeric_entry("Rows", 
                                        Theme.get_game_system_select_row_count, 
                                        Theme.set_game_system_select_row_count)
            )
            option_list.append(
                self.build_enabled_disabled_entry("Show Text", 
                                        Theme.get_system_select_show_text_grid_mode, 
                                        Theme.set_system_select_show_text_grid_mode)
            )
            option_list.append(
                self.build_enabled_disabled_entry("Show Sel BG", 
                                        Theme.get_system_select_show_sel_bg_grid_mode, 
                                        Theme.set_system_select_show_sel_bg_grid_mode)
            )
            
        return option_list
