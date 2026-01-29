
from controller.controller_inputs import ControllerInput
from display.on_screen_keyboard import OnScreenKeyboard
from menus.settings.theme.theme_settings_menu_common import ThemeSettingsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.view_type import ViewType


from menus.language.language import Language

class ThemeSettingsMainMenu(ThemeSettingsMenuCommon):
    def __init__(self):
        super().__init__()
        self.on_screen_keyboard = OnScreenKeyboard()

    def main_menu_title(self, input_value):
        if(ControllerInput.A == input_value):
            new_title = self.on_screen_keyboard.get_input(
                "Main Menu Title",
                Theme.get_main_menu_title()
            )
            if(new_title is not None):
                Theme.set_main_menu_title(new_title)


    def build_options_list(self) -> list[GridOrListEntry]:
        option_list = []
        
        option_list.append(
            self.build_enabled_disabled_entry(
                primary_text=Language.skip_main_menu(),
                get_value_func=Theme.skip_main_menu,
                set_value_func=Theme.set_skip_main_menu
            )
        )

        option_list.append(
            self.build_enabled_disabled_entry(
                primary_text=Language.merge_main_menu_and_game_menu(),
                get_value_func=Theme.merge_main_menu_and_game_menu,
                set_value_func=Theme.set_merge_main_menu_and_game_menu
            )
        )

        if(Theme.skip_main_menu()):
            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text=Language.show_extras_in_system_select_menu(),
                    get_value_func=Theme.show_extras_in_system_select_menu,
                    set_value_func=Theme.set_show_extras_in_system_select_menu
                )
            )

        if(not Theme.skip_main_menu()):
            option_list.append(
                self.build_view_type_entry(
                    primary_text=Language.main_menu(),
                    get_value_func=Theme.get_view_type_for_main_menu,
                    set_value_func=Theme.set_view_type_for_main_menu
                )
            )

            if(ViewType.GRID == Theme.get_view_type_for_main_menu()):
                option_list.append(
                    self.build_numeric_entry(
                        primary_text=Language.main_menu_columns(),
                        get_value_func=Theme.get_main_menu_column_count,
                        set_value_func=Theme.set_main_menu_column_count
                    )
                )
                option_list.append(
                    self.build_enabled_disabled_entry(
                        primary_text=Language.show_text(),
                        get_value_func=Theme.get_main_menu_show_text_grid_mode,
                        set_value_func=Theme.set_main_menu_show_text_grid_mode
                    )
                )
                option_list.append(
                    self.build_enabled_disabled_entry("Wrap-Around", 
                        Theme.get_main_menu_grid_wrap_around_single_row, 
                        Theme.set_main_menu_grid_wrap_around_single_row)
                    )            
        if(not Theme.skip_main_menu() or Theme.show_extras_in_system_select_menu()):
            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text=Language.show_recents(),
                    get_value_func=Theme.get_recents_enabled,
                    set_value_func=Theme.set_recents_enabled
                )
            )

            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text=Language.show_collections(),
                    get_value_func=Theme.get_collections_enabled,
                    set_value_func=Theme.set_collections_enabled
                )
            )
            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text=Language.show_favorites(),
                    get_value_func=Theme.get_favorites_enabled,
                    set_value_func=Theme.set_favorites_enabled
                )
            )
            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text=Language.show_apps(),
                    get_value_func=Theme.get_apps_enabled,
                    set_value_func=Theme.set_apps_enabled
                )
            )
            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text=Language.show_settings(),
                    get_value_func=Theme.get_settings_enabled,
                    set_value_func=Theme.set_settings_enabled
                )
            )
            option_list.append(
                GridOrListEntry(
                    primary_text="Main Menu Title",
                    value_text=Theme.get_main_menu_title(),
                    value=self.main_menu_title
                )
            )

        return option_list
