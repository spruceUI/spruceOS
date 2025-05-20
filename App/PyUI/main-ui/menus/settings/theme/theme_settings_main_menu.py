
from controller.controller_inputs import ControllerInput
from menus.settings.theme.theme_settings_menu_common import ThemeSettingsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.view_type import ViewType


class ThemeSettingsMainMenu(ThemeSettingsMenuCommon):
    def __init__(self):
        super().__init__()


    def build_options_list(self) -> list[GridOrListEntry]:
        option_list = []
        
        option_list.append(
            self.build_enabled_disabled_entry(
                primary_text="Skip Main Menu",
                get_value_func=Theme.skip_main_menu,
                set_value_func=Theme.set_skip_main_menu
            )
        )

        if(not Theme.skip_main_menu()):
            option_list.append(
                self.build_view_type_entry(
                    primary_text="Main Menu",
                    get_value_func=Theme.get_view_type_for_main_menu,
                    set_value_func=Theme.set_view_type_for_main_menu
                )
            )

            if(ViewType.GRID == Theme.get_view_type_for_main_menu()):
                option_list.append(
                    self.build_numeric_entry(
                        primary_text="Main Menu Columns",
                        get_value_func=Theme.get_main_menu_column_count,
                        set_value_func=Theme.set_main_menu_column_count
                    )
                )
                option_list.append(
                    self.build_enabled_disabled_entry(
                        primary_text="Show Text",
                        get_value_func=Theme.get_main_menu_show_text_grid_mode,
                        set_value_func=Theme.set_main_menu_show_text_grid_mode
                    )
                )
            
            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text="Show Recents",
                    get_value_func=Theme.get_recents_enabled,
                    set_value_func=Theme.set_recents_enabled
                )
            )
            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text="Show Favorites",
                    get_value_func=Theme.get_favorites_enabled,
                    set_value_func=Theme.set_favorites_enabled
                )
            )
            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text="Show Apps",
                    get_value_func=Theme.get_apps_enabled,
                    set_value_func=Theme.set_apps_enabled
                )
            )
            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text="Show Settings",
                    get_value_func=Theme.get_settings_enabled,
                    set_value_func=Theme.set_settings_enabled
                )
            )
        return option_list
