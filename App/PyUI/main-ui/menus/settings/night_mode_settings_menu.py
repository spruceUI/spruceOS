from menus.settings import shared_display_settings_menu


class NightModeSettingsMenu(shared_display_settings_menu.SharedDisplaySettingsMenu):
    SETTINGS_CATEGORY = "Night Mode Settings"

    def __init__(self):
        super().__init__()