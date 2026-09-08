
import subprocess
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

    def get_timezone_mode(self):
        system_config = Device.get_device().get_system_config()
        if hasattr(system_config, "get_timezone_mode"):
            return system_config.get_timezone_mode()
        return "manual"

    def change_timezone_mode_setting(self, input):
        if (ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input or ControllerInput.A == input):
            system_config = Device.get_device().get_system_config()
            if not hasattr(system_config, "set_timezone_mode"):
                return
            if self.get_timezone_mode() == "auto":
                system_config.set_timezone_mode("manual")
            else:
                system_config.set_timezone_mode("auto")
                # Detect now rather than at the next network-up. syncTime.sh
                # runs the same code networkservices.sh does, detached because
                # it talks to the network; PyUI picks the result up from the
                # shared config file.
                try:
                    subprocess.Popen(["/mnt/SDCARD/spruce/scripts/syncTime.sh"])
                except Exception as e:
                    PyUiLogger.get_logger().error(f"Failed to launch timezone detection: {e}")

    def change_24_hour_clock_setting(self, input):
        if (ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input or ControllerInput.A == input):
            PyUiConfig.set_use_24_hour_clock(
                not PyUiConfig.use_24_hour_clock())


    def change_sync_time_via_network_setting(self, input):
        if (ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input or ControllerInput.A == input):
            enabled = not PyUiConfig.sync_time_via_network()
            PyUiConfig.set_sync_time_via_network(enabled)
            if enabled:
                # Apply it here rather than leaving the clock wrong until the
                # next game exit, which is when networkservices.sh would
                # otherwise next run. Detached, because an NTP attempt can take
                # many seconds and the menu must not freeze on it. The script
                # re-reads the toggle and does nothing if the clock is already
                # right, so a stray launch is harmless.
                try:
                    subprocess.Popen(["/mnt/SDCARD/spruce/scripts/syncTime.sh"])
                except Exception as e:
                    PyUiLogger.get_logger().error(f"Failed to launch time sync: {e}")


    def change_am_pm_setting(self, input):
        if (ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input or ControllerInput.A == input):
            PyUiConfig.set_show_am_pm(
                not PyUiConfig.show_am_pm())


    def set_time(self, input):
        if (ControllerInput.A == input):
            SetTimeMenu().show_menu()

    def get_current_timezone(self):
        system_config = Device.get_device().get_system_config()
        if hasattr(system_config, "get_timezone"):
            return system_config.get_timezone()
        return getattr(system_config, "timezone", None)


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
                    value_text="<    " + (self.get_current_timezone() or "") + "    >",
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value=self.set_timezone
                )
            )
            if(Device.get_device().supports_automatic_timezone()):
                mode_auto = self.get_timezone_mode() == "auto"
                option_list.append(
                    GridOrListEntry(
                        primary_text=Language.get("timezoneMode", "Timezone mode"),
                        value_text="<    " + (Language.get("timezoneModeAuto", "Automatic") if mode_auto else Language.get("timezoneModeManual", "Manual")) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=Language.get("timezoneModeDesc", "Automatic sets the zone from your network location when online; picking a zone above switches to Manual"),
                        icon=None,
                        value=self.change_timezone_mode_setting
                    )
                )
        else:
            PyUiLogger.get_logger().info("Timezone setting not supported on this Device.get_device().")

        # Only where there is a radio to sync over. Shown for every such device,
        # not just the ones with no RTC, because it is the user's call: turning
        # it off holds the clock wherever they set it, which is the point for
        # anyone timing in-game events off it.
        if(Device.get_device().supports_wifi()):
            option_list.append(
                GridOrListEntry(
                    primary_text=Language.sync_time_via_network(),
                    value_text="<    " +
                    ("On" if PyUiConfig.sync_time_via_network() else "Off") + "    >",
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value=self.change_sync_time_via_network_setting
                )
            )

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

