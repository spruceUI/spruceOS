
from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from menus.settings.set_time_menu import SetTimeMenu
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

class TimeSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def set_timezone(self, input):
        if (ControllerInput.A == input):
            Device.get_device().prompt_timezone_update()

    def change_24_hour_clock_setting(self, input):
        if (ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input or ControllerInput.A == input):
            PyUiConfig.set_use_24_hour_clock(
                not PyUiConfig.use_24_hour_clock())


    def change_am_pm_setting(self, input):
        if (ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input or ControllerInput.A == input):
            PyUiConfig.set_show_am_pm(
                not PyUiConfig.show_am_pm())


    def set_time(self, input):
        if (ControllerInput.A == input):
            SetTimeMenu().show_menu()


    def build_options_list(self):
        option_list = []


        option_list.append(
            GridOrListEntry(
                primary_text=Language.set_time_date(),
                value_text=None,
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.set_time
            )
        )

        if(Device.get_device().supports_timezone_setting()):
            option_list.append(
                GridOrListEntry(
                    primary_text=Language.set_timezone(),
                    value_text=None,
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value=self.set_timezone
                )
            )
        else:
            PyUiLogger.get_logger().info("Timezone setting not supported on this Device.get_device().")

        option_list.append(
            GridOrListEntry(
                primary_text=Language.twenty_four_hour_clock(),
                value_text="<    " +
                 ("On" if PyUiConfig.use_24_hour_clock() else "Off") + "    >",
                 image_path=None,
                 image_path_selected=None,
                 description=None,
                 icon=None,
                 value=self.change_24_hour_clock_setting
            )
        )
        option_list.append(
                GridOrListEntry(
                    primary_text=Language.show_am_pm(),
                    value_text="<    " +
                    ("On" if PyUiConfig.show_am_pm() else "Off") + "    >",
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value=self.change_am_pm_setting
               )
        )

        return option_list

