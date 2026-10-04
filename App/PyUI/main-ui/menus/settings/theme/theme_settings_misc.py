
from display.display import Display
from display.font_purpose import FontPurpose
from menus.language.language import Language
from menus.settings.theme.theme_settings_menu_common import ThemeSettingsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry


class ThemeSettingsMisc(ThemeSettingsMenuCommon):
    def __init__(self):
        super().__init__()

    def selection_made(self):
        Display.clear_text_cache()

    def build_options_list(self) -> list[GridOrListEntry]:
        option_list = []
        option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text=Language.useTextForLineHeight(),
                    get_value_func=lambda  :  Theme.get_use_text_for_line_height(),
                    set_value_func=lambda  val :  Theme.set_use_text_for_line_height(val)
                )
            )        

        option_list.append(
            self.build_defined_list_entry(
                primary_text=Language.image_list_view_mode(),
                all_options=["TEXT_LEFT_IMAGE_RIGHT","TEXT_RIGHT_IMAGE_LEFT","TEXT_ABOVE_IMAGE","TEXT_BELOW_IMAGE"],
                get_value_func=Theme.text_and_image_list_view_mode,
                set_value_func=Theme.set_text_and_image_list_view_mode,
            )
        )

        if(Theme.text_and_image_list_view_mode() in ["TEXT_ABOVE_IMAGE", "TEXT_BELOW_IMAGE"]):
            option_list.append(
                self.build_numeric_entry(
                    primary_text=Language.image_top_bottom_percent(),
                    get_value_func=Theme.get_img_percent_top_bottom_view,
                    set_value_func=Theme.set_img_percent_top_bottom_view,
                    min=1,
                    max=99
                )
            )


        return option_list
