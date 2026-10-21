from menus.settings import settings_menu


class NightModeSettingsMenu(settings_menu.SettingsMenu):
    SETTINGS_CATEGORY = "Night Mode Settings"

    def __init__(self):
        super().__init__()

    def build_options_list(self):
        return self.build_options_list_from_config_menu_options(self.SETTINGS_CATEGORY)
