
import os
from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from menus.settings.timezone_menu import TimezoneMenu
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry


class TimeSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def set_timezone(self, input):
        if (ControllerInput.A == input):
            tz = TimezoneMenu().ask_user_for_timezone()
            if (tz is not None):
                PyUiConfig.set_timezone(tz)

    def change_show_clock(self, input):
        if (ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input or ControllerInput.A == input):
            PyUiConfig.set_show_clock(not PyUiConfig.show_clock())

    def change_24_hour_clock_setting(self, input):
        if (ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input or ControllerInput.A == input):
            PyUiConfig.set_use_24_hour_clock(
                not PyUiConfig.use_24_hour_clock())


    def change_am_pm_setting(self, input):
        if (ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input or ControllerInput.A == input):
            PyUiConfig.set_show_am_pm(
                not PyUiConfig.show_am_pm())

    def build_options_list(self):
        option_list = []
        option_list.append(
            GridOrListEntry(
                primary_text="Set Timezone",
                value_text=None,
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.set_timezone
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text="Clock",
                value_text="<    " +
                ("On" if PyUiConfig.show_clock() else "Off") + "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.change_show_clock
            )
        )
        if (PyUiConfig.show_clock()):
            option_list.append(
                GridOrListEntry(
                    primary_text="24 Hour Clock",
                    value_text="<    " +
                    ("On" if PyUiConfig.use_24_hour_clock() else "Off") + "    >",
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value=self.change_24_hour_clock_setting
                )
            )
            if (not PyUiConfig.use_24_hour_clock()):
                option_list.append(
                    GridOrListEntry(
                        primary_text="Show AM/PM",
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
