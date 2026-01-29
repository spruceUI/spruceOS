
from menus.settings import settings_menu


class CfwSystemSettingsMenuForCategory(settings_menu.SettingsMenu):
    def __init__(self, category):
        self.category = category
        super().__init__()


    def build_options_list(self):
        return self.build_options_list_from_config_menu_options(self.category)