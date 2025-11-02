
from display.display import Display
from display.font_purpose import FontPurpose
from menus.settings.theme.theme_settings_menu_common import ThemeSettingsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry


class ThemeSettingsFonts(ThemeSettingsMenuCommon):
    def __init__(self):
        super().__init__()

    def selection_made(self):
        Display.clear_text_cache()

    def build_options_list(self) -> list[GridOrListEntry]:
        option_list = []
        
        for purpose in FontPurpose:
            if(FontPurpose.ON_SCREEN_KEYBOARD != purpose):
                option_list.append(
                    self.build_numeric_entry(
                        primary_text=purpose.name + " Size",
                        get_value_func=lambda font_purpose=purpose :  Theme.get_font_size(font_purpose),
                        set_value_func=lambda size, font_purpose=purpose :  Theme.set_font_size(font_purpose,size)
                    )
                )
        return option_list
