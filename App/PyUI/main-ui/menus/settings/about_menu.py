
from devices.device import Device
from menus.settings import settings_menu
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
import subprocess


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

        if PyUiConfig.get_about_entries():
            for entry in PyUiConfig.get_about_entries():
                display = entry.get("display", "")
                cmd = entry.get("cmd", "")

                option_list.append(
                    GridOrListEntry(
                        primary_text=display,
                        value_text=self.get_value_from_cmd(cmd) if cmd else "",
                        description=None,
                        value=self.do_nothing
                    )
                )



            

        return option_list

    def get_value_from_cmd(self, cmd):
        try:
            result = subprocess.run(
                cmd,
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=True
            )
            return result.stdout.strip()
        except Exception as e:
            PyUiLogger.get_logger().error(
                f"Error running {cmd} so returning empty string : {e}"
            )
            return ""
