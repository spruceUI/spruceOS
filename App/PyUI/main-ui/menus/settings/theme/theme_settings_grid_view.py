
from menus.settings.theme.theme_settings_menu_common import ThemeSettingsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

class ThemeSettingsGridView(ThemeSettingsMenuCommon):
    def __init__(self):
        super().__init__()


    def build_options_list(self) -> list[GridOrListEntry]:
        option_list = []
        option_list.append(
            self.build_numeric_entry(
                primary_text=Language.sel_bg_resize_pad_width(),
                get_value_func=Theme.get_grid_multi_row_sel_bg_resize_pad_width,
                set_value_func=Theme.set_grid_multi_row_sel_bg_resize_pad_width
            )
        )
        option_list.append(
            self.build_numeric_entry(
                primary_text=Language.sel_bg_resize_pad_height(),
                get_value_func=Theme.get_grid_multi_row_sel_bg_resize_pad_height,
                set_value_func=Theme.set_grid_multi_row_sel_bg_resize_pad_height
            )
        )
        option_list.append(
            self.build_numeric_entry(
                primary_text=Language.set_single_row_grid_text_y_offset(),
                get_value_func=Theme.single_row_grid_text_y_offset,
                set_value_func=Theme.set_single_row_grid_text_y_offset,
                min=-1000,
                max=10000
            )
        )
        option_list.append(
            self.build_numeric_entry(
                primary_text=Language.set_multi_row_grid_text_y_offset(),
                get_value_func=Theme.multi_row_grid_text_y_offset,
                set_value_func=Theme.set_multi_row_grid_text_y_offset,
                min=-1000,
                max=10000
            )
        )
        option_list.append(
            self.build_numeric_entry(
                primary_text=Language.set_grid_multi_row_img_y_offset(),
                get_value_func=Theme.get_grid_multi_row_img_y_offset_raw,
                set_value_func=Theme.set_grid_multi_row_img_y_offset,
                min=-1000,
                max=10000
            )
        )
        option_list.append(
            self.build_enabled_disabled_entry("Set Grid BG Offset To Image Offset",
                                                Theme.grid_bg_offset_to_image_offset,
                                                Theme.set_grid_bg_offset_to_image_offset)
        )        

        return option_list
