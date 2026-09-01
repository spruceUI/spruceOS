from devices.anbernic.anbernic_xx_common import AnbernicXXCommon
from utils.logger import PyUiLogger
import os


class AnbernicRG28xx(AnbernicXXCommon):
    """The XX line's portrait-panel, USB-radio model.

    TEMPORARY (2026-09-01): presented as a device WITHOUT WiFi. The shipped
    8188eu.ko does not load on BaseOS (SPR-MED-177), so there is never a
    wlan0; declaring the radio absent removes the WiFi state from the top bar,
    drops the WiFi entry from Settings, and keeps this class from writing a
    supplicant config or starting wpa_supplicant/udhcpc. The shell makes the
    same call in spruce/scripts/platform/device_functions/AnbernicRG28XX.sh.
    Delete the six overrides below to restore WiFi once the driver is fixed.
    """

    def __init__(self, main_ui_mode):
        # For now
        self.device_name = "ANBERNIC_RG28XX"
        super().__init__(main_ui_mode)

    def screen_width(self):
        return 640

    def screen_height(self):
        return 480

    def screen_rotation(self):
        return 0

    def supports_wifi(self):
        return False

    def is_wifi_enabled(self):
        return False

    def get_wifi_menu(self):
        return None

    def ensure_wpa_supplicant_conf(self):
        # AnbernicXXCommon.__init__ calls this in main-UI mode; nothing on this
        # model reads the file, so do not create it.
        pass

    def enable_wifi(self):
        PyUiLogger.get_logger().info("RG28XX runs as a no-WiFi device; enable_wifi ignored")

    def disable_wifi(self):
        PyUiLogger.get_logger().info("RG28XX runs as a no-WiFi device; disable_wifi ignored")
