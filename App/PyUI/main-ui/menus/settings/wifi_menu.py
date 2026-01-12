
from asyncio import subprocess
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
        else:
            Device.get_device().enable_wifi()

    def write_wpa_supplicant_conf(self, ssid, pw_line):
        file_path = Device.get_device().get_wpa_supplicant_conf_path()
        # WPA configuration header
        header = """ctrl_interface=/var/run/wpa_supplicant
    update_config=1
    """

        # Build the new network block
        new_network = f"""
    network={{
        ssid="{ssid}"
        {pw_line}
    }}
    """

        try:
            # Read the existing file if it exists
            existing_content = ""
            if os.path.exists(file_path):
                with open(file_path, "r") as f:
                    existing_content = f.read().strip()

            # Ensure the file starts with the required header
            if not existing_content.startswith("ctrl_interface"):
                existing_content = header + "\n" + existing_content

            # Regex to locate a block for this SSID
            ssid_pattern = re.compile(
                r'network\s*\{\s*ssid="' + re.escape(ssid) + r'".*?\}',
                re.DOTALL
            )

            if ssid_pattern.search(existing_content):
                # Replace the existing block for this SSID
                updated_content = ssid_pattern.sub(new_network.strip(), existing_content)
                PyUiLogger.get_logger().info(f"Updated existing network '{ssid}' in {file_path}")
            else:
                # Append the new network at the end
                updated_content = existing_content.rstrip() + "\n" + new_network.strip() + "\n"
                PyUiLogger.get_logger().info(f"Added new network '{ssid}' to {file_path}")

            # Write the updated content back to the file
            with open(file_path, "w") as f:
                f.write(updated_content)

        except IOError as e:
            PyUiLogger.get_logger().error(f"Error writing to {file_path}: {e}")


    def reload_wpa_supplicant_config(self):
        try:
            ProcessRunner.run(["wpa_cli", "reconfigure"])
            PyUiLogger.get_logger().info("wpa_supplicant.conf reloaded successfully.")
        except subprocess.CalledProcessError as e:
            PyUiLogger.get_logger().error(f"Error reloading wpa_supplicant.conf: {e}")


    #TODO add confirmation or failed popups
    def switch_network(self, net: WiFiNetwork):
        PyUiLogger.get_logger().info(f"Selected {net.ssid}!")
        if(net.requires_password()):
            password = self.on_screen_keyboard.get_input("WiFi Password")
            if(password is not None and 8 <= len(password) <= 63):
                self.write_wpa_supplicant_conf(net.ssid, "psk=\""+password+"\"")
        else:   
            self.write_wpa_supplicant_conf(net.ssid, "key_mgmt=NONE")

        self.reload_wpa_supplicant_config()

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
                for net in networks:
                    name = net.ssid
                    is_5ghz = 5000 <= net.frequency <= 6000

                    if is_5ghz:
                        name += " (5Ghz)"

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
        self.wifi_scanner = WiFiScanner()

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
