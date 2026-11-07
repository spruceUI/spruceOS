from pathlib import Path
from menus.settings.wifi_menu import WifiMenu

from display.display import Display

class USBWifiMenu(WifiMenu):
    def __init__(self):
        super().__init__()

    def adapter_is_connected(self):
        interfaces = Path("/sys/class/net/")

        for i in interfaces.iterdir():
            if i.name.startswith("eth") or i.name.startswith("wlan"):
                return True

        return False

    def show_wifi_menu(self):
        if self.adapter_is_connected():
            super().show_wifi_menu()
        else:
            message = "USB adapter not connected.\n" \
                    "Connect a compatible adapter to use WiFi."
            Display.display_message(message, 5000)
