
from controller.controller_inputs import ControllerInput
from menus.settings.theme.theme_settings_menu_common import ThemeSettingsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry


class ThemeSettingsGameSelectMenu(ThemeSettingsMenuCommon):
    def __init__(self):
        super().__init__()

    def build_options_list(self) -> list[GridOrListEntry]:
        option_list = []
        option_list.append(
            GridOrListEntry(
                primary_text="Game Sel Menu",
                value_text="<    " + Theme.get_game_selection_view_type().name + "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=lambda input: self.change_view_type(
                    input, Theme.get_game_selection_view_type, Theme.set_game_selection_view_type)
            )
        )
        return option_list
