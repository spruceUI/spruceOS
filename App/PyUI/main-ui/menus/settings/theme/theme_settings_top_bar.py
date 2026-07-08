
from display.display import Display
from menus.settings.theme.theme_settings_menu_common import ThemeSettingsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

class ThemeSettingsTopAndBottomBar(ThemeSettingsMenuCommon):
    def __init__(self):
        super().__init__()

    def selection_made(self):
        Display.clear_text_cache()

    def build_options_list(self) -> list[GridOrListEntry]:
        option_list = []

        option_list.append(
            self.build_numeric_entry(
                primary_text=Language.left_side_initial_x_offset(),
                get_value_func=Theme.get_top_bar_initial_x_offset,
                set_value_func=Theme.set_top_bar_initial_x_offset
            )
        )
                
        option_list.append(
            self.build_enabled_disabled_entry(Language.label("showBatteryPercent", "Show Battery Percent"),
                                              Theme.display_battery_percent,
                                              Theme.set_display_battery_percent)
        )

        option_list.append(
            self.build_enabled_disabled_entry(Language.label("showBatteryIcon", "Show Battery Icon"),
                                              Theme.display_battery_icon,
                                              Theme.set_display_battery_icon)
        )

        option_list.append(
            self.build_enabled_disabled_entry(Language.label("showVolumeNumbers", "Show Volume Numbers"),
                                              Theme.display_volume_numbers,
                                              Theme.set_display_volume_numbers)
        )

        option_list.append(
            self.build_enabled_disabled_entry(Language.label("showBottomBarButtons", "Show Bottom Bar Buttons"),
                                              Theme.show_bottom_bar_buttons,
                                              Theme.set_show_bottom_bar_buttons)
        )

        option_list.append(
            self.build_enabled_disabled_entry(Language.label("showClock", "Show Clock"),
                                              Theme.show_clock,
                                              Theme.set_show_clock)
        )

        option_list.append(
            self.build_enabled_disabled_entry("Render Top Bar Last",
                                              Theme.render_top_and_bottom_bar_last,
                                              Theme.set_render_top_and_bottom_bar_last)
        )



        return option_list
