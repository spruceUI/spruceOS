from pathlib import Path
import time
from controller.controller_inputs import ControllerInput
from devices.device import Device
from devices.gkd.connman_wifi_scanner import WiFiNetwork
from display.display import Display
from display.on_screen_keyboard import OnScreenKeyboard
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType

from menus.language.language import Language

class ConnmanWifiMenu:
    def __init__(self):
        self.on_screen_keyboard = OnScreenKeyboard()

    def wifi_adjust(self):
        if Device.get_device().is_wifi_enabled():
            Device.get_device().disable_wifi()
        else:
            Device.get_device().enable_wifi()
        Device.get_device().note_wifi_change()


    #TODO add confirmation or failed popups
    def switch_network(self, net: WiFiNetwork):
        # Same shim as WifiMenu: the prompt is UI, joining is wifi.sh's job, and
        # the Pixel 2's device_wifi_connect hook does the connman work.
        PyUiLogger.get_logger().info(f"Selected {net.ssid}!")
        if(net.requires_password()):
            password = self.on_screen_keyboard.get_input(Language.label("wifiPassword", "WiFi Password"))
            if(password is not None and 8 <= len(password) <= 63):
                Display.display_message(
                    Language.label("updatingWifiConfig", "Updating config file for {ssid} with password {password}")
                    .replace("{ssid}", net.ssid)
                    .replace("{password}", password),
                    duration_ms=5000,
                )
                Device.get_device().wifi_connect(net.ssid, password)
                Device.get_device().note_wifi_change()
            else:
                Display.display_message(Language.label("invalidWifiPasswordLength", "Invalid WiFi password length! Must be between 8 and 63"), duration_ms=5000)
        else:
            Device.get_device().wifi_connect(net.ssid, None)
            Device.get_device().note_wifi_change()

    def _build_options(
        self,
        wifi_enabled: bool,
        networks: list[WiFiNetwork],
        connected_ssid: str | None,
    ):
        option_list = []

        # WiFi toggle entry
        option_list.append(
            GridOrListEntry(
                primary_text=Language.status(),
                value_text="<    " + Language.on_off_label(wifi_enabled) + "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.wifi_adjust,
            )
        )

        # Network entries
        if wifi_enabled:
            if not networks:
                option_list.append(
                    GridOrListEntry(
                        primary_text="Scanning for networks...",
                        value_text=None,
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=lambda: None,
                    )
                )
            else:
                seen_names = set()
                for net in networks:
                    name = net.ssid

                    if name in seen_names:
                        continue

                    seen_names.add(name)
                    connected = connected_ssid == net.ssid

                    option_list.append(
                        GridOrListEntry(
                            primary_text=name,
                            value_text="✓" if connected else None,
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=lambda net=net: self.switch_network(net),
                        )
                    )

        return option_list

    def adapter_is_connected(self):
        interfaces = Path("/sys/class/net/")

        for i in interfaces.iterdir():
            if i.name in ["wlan0", "eth0"]:
                return True

        return False

    def show_wifi_menu(self):
        if self.adapter_is_connected():
            self._show_menu()
        else:
            message = "USB adapter not connected.\n" \
                    "Connect a compatible adapter to use WiFi.\n" \
                    "The device must be restarted to use WiFi after using sleep."
            Display.display_message(message, 5000)

    def _show_menu(self):
        selected = Selection(None, None, 0)
        self.wifi_scanner = Device.get_device().get_new_wifi_scanner()

        # Start background scanning immediately
        self.wifi_scanner.scan_networks()

        connected_ssid = None

        accepted_inputs = [
            ControllerInput.A,
            ControllerInput.DPAD_LEFT,
            ControllerInput.DPAD_RIGHT,
            ControllerInput.L1,
            ControllerInput.R1,
        ]

        try:
            while selected is not None:
                wifi_enabled = Device.get_device().is_wifi_enabled()

                # Pull latest scan snapshot (non-blocking)
                networks = (
                    self.wifi_scanner.scan_networks()
                    if wifi_enabled
                    else []
                )

                ssid = self.wifi_scanner.get_connected_ssid()
                connected_ssid = ssid

                # Build options (single source of truth)
                option_list = self._build_options(
                    wifi_enabled=wifi_enabled,
                    networks=networks,
                    connected_ssid=connected_ssid,
                )

                # Render view
                list_view = ViewCreator.create_view(
                    view_type=ViewType.ICON_AND_DESC,
                    top_bar_text="WiFi Configuration",
                    options=option_list,
                    selected_index=selected.get_index(),
                )

                # Single non-blocking poll
                selected = list_view.get_selection(accepted_inputs)

                if selected is None:
                    break

                if selected.get_input() in accepted_inputs:
                    selected.get_selection().value()
                elif ControllerInput.B == selected.get_input():
                    break

                # Prevent CPU spin
                time.sleep(0.05)

        finally:
            Display.display_message(Language.label("stoppingWifiScanner", "Stopping WiFi scanner..."))
            self.wifi_scanner.stop()
