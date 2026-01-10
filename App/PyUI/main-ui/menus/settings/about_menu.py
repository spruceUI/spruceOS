
from devices.device import Device
from menus.settings import settings_menu
from views.grid_or_list_entry import GridOrListEntry


class AboutMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def do_nothing(self, input_value):
        pass

    def build_options_list(self):
        option_list = []

        for text, value in Device.get_device().get_about_info_entries():
            option_list.append(
                GridOrListEntry(
                    primary_text=text,
                    value_text=value,
                    description=None,
                    value=self.do_nothing
                    )
                )

            

        return option_list