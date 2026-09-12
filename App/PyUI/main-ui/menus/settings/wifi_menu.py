
from asyncio import subprocess
import tempfile
import time
import os
import re
from controller.controller_inputs import ControllerInput
from devices.device import Device
from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_scanner import WiFiNetwork, WiFiScanner
from display.display import Display
from display.font_purpose import FontPurpose
from display.on_screen_keyboard import OnScreenKeyboard
from display.render_mode import RenderMode
from themes.theme import Theme
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


from menus.language.language import Language

class WifiMenu:
    def __init__(self):
        self.on_screen_keyboard = OnScreenKeyboard()

    def wifi_adjust(self):
        if Device.get_device().is_wifi_enabled():
            Device.get_device().disable_wifi()
            Device.get_device().note_wifi_change()
        else:
            Device.get_device().enable_wifi()
            Device.get_device().note_wifi_change()


    def reload_wpa_supplicant_config(self):
        try:
            ProcessRunner.run(["wpa_cli", "reconfigure"])
            PyUiLogger.get_logger().info("wpa_supplicant.conf reloaded successfully.")
        except subprocess.CalledProcessError as e:
            PyUiLogger.get_logger().error(f"Error reloading wpa_supplicant.conf: {e}")


    #TODO add confirmation or failed popups
    def switch_network(self, net: WiFiNetwork):
        # The password prompt stays here (it is UI); applying the selection is
        # the device's job, so a host with its own network stack can do it that
        # way. The default
        # device implementation is the wpa_supplicant behaviour this method used
        # to inline.
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
        connected_is_5ghz: bool,
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
                        primary_text=Language.label("scanningForNetworks", "Scanning for networks..."),
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
                    is_5ghz = 5000 <= net.frequency <= 6000

                    if is_5ghz:
                        name += " (5Ghz)"

                    if name in seen_names:
                        continue

                    seen_names.add(name)
                    connected = (
                        connected_ssid == net.ssid
                        and is_5ghz == connected_is_5ghz
                    )


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


    def show_wifi_menu(self):
        selected = Selection(None, None, 0)
        self.wifi_scanner = Device.get_device().get_new_wifi_scanner()

        # Start background scanning immediately
        self.wifi_scanner.scan_networks()

        connected_ssid = None
        connected_is_5ghz = False

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

                ssid, freq = self.wifi_scanner.get_connected_ssid()
                connected_ssid = ssid
                connected_is_5ghz = bool(freq and 5000 <= freq <= 6000)

                # Build options (single source of truth)
                option_list = self._build_options(
                    wifi_enabled=wifi_enabled,
                    networks=networks,
                    connected_ssid=connected_ssid,
                    connected_is_5ghz=connected_is_5ghz,
                )

                # Render view
                list_view = ViewCreator.create_view(
                    view_type=ViewType.ICON_AND_DESC,
                    top_bar_text=Language.label("wifiConfiguration", "WiFi Configuration"),
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
