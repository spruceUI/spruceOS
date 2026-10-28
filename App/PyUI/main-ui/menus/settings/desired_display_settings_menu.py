from menus.settings import shared_display_settings_menu

class DesiredDisplaySettingsMenu(shared_display_settings_menu.SharedDisplaySettingsMenu):
    SETTINGS_CATEGORY = "Desired Display Settings"

    def __init__(self):
        super().__init__()
