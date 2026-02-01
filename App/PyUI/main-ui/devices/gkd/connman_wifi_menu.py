from asyncio import subprocess
from pathlib import Path
import configparser
import time
from controller.controller_inputs import ControllerInput
from devices.device import Device
from devices.gkd.connman_wifi_scanner import WiFiNetwork
from devices.utils.process_runner import ProcessRunner
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


    def write_connman_conf(self, network: WiFiNetwork, passwd: str):
        config_folder = Path("/storage/.cache/connman")

        # Build config options
        config = configparser.RawConfigParser()
        config.optionxform = lambda option: option

        config.add_section("Settings")
        config["Settings"]["AutoConnect"] = "true"

        net_section = f"service_{network.id_str}"
        config.add_section(net_section)
        config[net_section]["Type"] = "wifi"
        config[net_section]["Name"] = network.ssid
        config[net_section]["Passphrase"] = passwd

        filename = network.id_str.split("_")[2]
        full_path = config_folder.joinpath(filename).with_suffix(".config")

        # Write to file
        try:
            with open(full_path, "w") as f:
                config.write(f)

            PyUiLogger.get_logger().info(
                f"Installed network '{network.ssid}' into {str(full_path)}"
            )

        except OSError as e:
            PyUiLogger.get_logger().error(f"Failed writing {str(full_path)}: {e}")


    def connman_connect(self, id_str: str):
        try:
            ProcessRunner.run(["connmanctl", "connect", id_str])
            PyUiLogger.get_logger().info(f"Connected to {id_str}.")
        except subprocess.CalledProcessError as e:
            PyUiLogger.get_logger().error(f"Error connecting to {id_str}: {e}")


    #TODO add confirmation or failed popups
    def switch_network(self, net: WiFiNetwork):
        PyUiLogger.get_logger().info(f"Selected {net.ssid}!")
        if(net.requires_password()):
            password = self.on_screen_keyboard.get_input("WiFi Password")
            if(password is not None and 8 <= len(password) <= 63):
                self.write_connman_conf(net, password)
                Display.display_message(f"Updating config file for {net.ssid} with password {password}", duration_ms=5000)
            else:
                Display.display_message("Invalid WiFi password length! Must be between 8 and 63", duration_ms=5000)

        self.connman_connect(net.id_str)

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
                value_text="<    " + ("On" if wifi_enabled else "Off") + "    >",
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
            if i.name == "wlan0":
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
            Display.display_message("Stopping WiFi scanner...")
            self.wifi_scanner.stop()
