
from display.resize_type import get_next_resize_type
from menus.settings.theme.theme_settings_menu_common import ThemeSettingsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.view_type import ViewType


from menus.language.language import Language

class ThemeSettingsGameSelectMenu(ThemeSettingsMenuCommon):
    def __init__(self):
        super().__init__()

    def build_options_list(self) -> list[GridOrListEntry]:
        option_list = []
        option_list.append(
            self.build_view_type_entry(
                primary_text=Language.game_sel_menu(),
                get_value_func=Theme.get_game_selection_view_type,
                set_value_func=Theme.set_game_selection_view_type
            )
        )
        if (ViewType.GRID == Theme.get_game_selection_view_type()):
            option_list += self.build_grid_specific_options()
        elif (ViewType.CAROUSEL == Theme.get_game_selection_view_type()):
            option_list += self.build_carousel_specific_options()
        elif(ViewType.FULLSCREEN_GRID == Theme.get_game_selection_view_type()):
            option_list += self.build_full_screen_grid_specific_options()
        return option_list

    def build_grid_specific_options(self):
        option_list = []
        option_list.append(
            self.build_enum_entry(
                primary_text=Language.img_mode(),
                get_value_func=Theme.get_grid_game_selected_resize_type,
                set_value_func=Theme.set_grid_game_selected_resize_type,
                get_next_enum_type=get_next_resize_type
            )
        )
        option_list.append(
            self.build_numeric_entry(
                primary_text=Language.rows(),
                get_value_func=Theme.get_game_select_row_count,
                set_value_func=Theme.set_game_select_row_count
            )
        )
        option_list.append(
            self.build_numeric_entry(
                primary_text=Language.cols(),
                get_value_func=Theme.get_game_select_col_count,
                set_value_func=Theme.set_game_select_col_count
            )
        )
        option_list.append(
            self.build_numeric_entry(
                primary_text=Language.img_width(),
                get_value_func=Theme.get_game_select_img_width,
                set_value_func=Theme.set_game_select_img_width
            )
        )
        option_list.append(
            self.build_numeric_entry(
                primary_text=Language.img_height(),
                get_value_func=Theme.get_game_select_img_height,
                set_value_func=Theme.set_game_select_img_height
            )
        )
        option_list.append(
            self.build_enabled_disabled_entry("Show Text",
                                              Theme.get_game_select_show_text_grid_mode,
                                              Theme.set_game_select_show_text_grid_mode)
        )
        option_list.append(
            self.build_enabled_disabled_entry("Show Sel BG",
                                              Theme.get_game_select_show_sel_bg_grid_mode,
                                              Theme.set_game_select_show_sel_bg_grid_mode)
        )

        option_list.append(
            self.build_enabled_disabled_entry("TopBar = GameName",
                                              Theme.get_set_top_bar_text_to_game_selection,
                                              Theme.set_set_top_bar_text_to_game_selection)
        )
        return option_list

    def build_carousel_specific_options(self):
        option_list = []
        option_list.append(
            self.build_numeric_entry(
                primary_text=Language.cols(),
                get_value_func=Theme.get_game_select_carousel_col_count,
                set_value_func=Theme.set_game_select_carousel_col_count
            )
        )
        option_list.append(
            self.build_percent_entry(
                primary_text=Language.prim_img_width(),
                get_value_func=Theme.get_carousel_game_select_primary_img_width,
                set_value_func=Theme.set_carousel_game_select_primary_img_width
            )
        )
        option_list.append(
            self.build_enabled_disabled_entry(
                "TopBar = GameName",
                Theme.get_set_top_bar_text_to_game_selection,
                Theme.set_set_top_bar_text_to_game_selection)
        )
        if (Theme.get_game_select_carousel_col_count() > 3):
            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text=Language.shrink_further_away(),
                    get_value_func=Theme.get_carousel_game_select_shrink_further_away,
                    set_value_func=Theme.set_carousel_game_select_shrink_further_away
                )
            )

        if (not Theme.get_carousel_game_select_shrink_further_away()):
            option_list.append(
                self.build_enabled_disabled_entry(
                    "Sides Hang Off",
                    Theme.get_carousel_game_select_sides_hang_off,
                    Theme.set_carousel_game_select_sides_hang_off)
            )
        return option_list

    def build_full_screen_grid_specific_options(self):
        option_list = []
        option_list.append(
            self.build_enabled_disabled_entry(
                "TopBar = GameName",
                Theme.get_set_top_bar_text_to_game_selection,
                Theme.set_set_top_bar_text_to_game_selection)
        )

        option_list.append(
            self.build_enum_entry(
                primary_text=Language.boxart_resize_type(),
                get_value_func=Theme.get_full_screen_grid_game_menu_resize_type,
                set_value_func=Theme.set_full_screen_grid_game_menu_resize_type,
                get_next_enum_type=get_next_resize_type
            )
        )
        
        return option_list
