
import os
import re
from controller.controller_inputs import ControllerInput
from devices.device import Device
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
        self.wifi_scanner = WiFiScanner()
        self.on_screen_keyboard = OnScreenKeyboard()

    def wifi_adjust(self):
        if Device.is_wifi_enabled():
            Device.disable_wifi()
        else:
            Device.enable_wifi()

    def write_wpa_supplicant_conf(self, ssid, pw_line):
        file_path = Device.get_wpa_supplicant_conf_path()
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


    #TODO add confirmation or failed popups
    def switch_network(self, net: WiFiNetwork):
        PyUiLogger.get_logger().info(f"Selected {net.ssid}!")
        if(net.requires_password):
            password = self.on_screen_keyboard.get_input("WiFi Password")
            if(password is not None and 8 <= len(password) <= 63):
                self.write_wpa_supplicant_conf(net.ssid, "psk=\""+password+"\"")
        else:   
            self.write_wpa_supplicant_conf(net.ssid, "key_mgmt=NONE")

        self.wifi_scanner.reload_wpa_supplicant_config()


    def show_wifi_menu(self):
        selected = Selection(None, None, 0)
        should_scan_for_wifi = True
        networks = []
        connected_ssid = ""
        connected_freq = 0
        connected_is_5ghz = False
        while(selected is not None):
            wifi_enabled = Device.is_wifi_enabled()
            option_list = []
            option_list.append(
                GridOrListEntry(
                        primary_text=Language.status(),
                        value_text="<    " + ("On" if wifi_enabled else "Off") + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.wifi_adjust
                    )
            )
            

            if(wifi_enabled):
                Display.clear("WiFi")
                Display.render_text(
                    text = "Scanning for Networks (~10s)",
                    x = Device.screen_width() // 2,
                    y = Display.get_usable_screen_height() // 2,
                    color = Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_TITLE),
                    purpose = FontPurpose.DESCRIPTIVE_LIST_TITLE,
                    render_mode=RenderMode.MIDDLE_CENTER_ALIGNED)
                Display.present()
                if(should_scan_for_wifi):
                    should_scan_for_wifi = False
                    networks = self.wifi_scanner.scan_networks()
                    connected_ssid, connected_freq = self.wifi_scanner.get_connected_ssid()
                    connected_is_5ghz = False
                    if(connected_freq is not None and connected_freq >= 5000 and connected_freq <= 6000):
                        connected_is_5ghz = True

                for net in networks:
                    network_name = net.ssid
                    network_is_5ghz = False
                    if(net.frequency >= 5000 and net.frequency <= 6000):
                        network_name += " (5Ghz)"
                        network_is_5ghz = True

                    connected = False
                    if(connected_ssid == net.ssid and network_is_5ghz == connected_is_5ghz):
                        connected = True

                    option_list.append(
                        GridOrListEntry(
                                primary_text=network_name,
                                value_text="✓" if connected else None,
                                image_path=None,
                                image_path_selected=None,
                                description=None,
                                icon=None,
                                value=lambda net=net: self.switch_network(net)  # Capture net at creation
                            )
                    )

            list_view = ViewCreator.create_view(
                    view_type=ViewType.ICON_AND_DESC,
                    top_bar_text="WiFi Configuration", 
                    options=option_list,
                    selected_index=selected.get_index())

            accepted_inputs = [ControllerInput.A, ControllerInput.DPAD_LEFT, ControllerInput.DPAD_RIGHT,
                                                ControllerInput.L1, ControllerInput.R1]
            
            selected = Selection(None, None, 0)
            while(selected is not None and selected.get_input() not in accepted_inputs):
                selected = list_view.get_selection(accepted_inputs)

                if(selected.get_input() in accepted_inputs):
                    selected.get_selection().value()
                    should_scan_for_wifi = True
                elif(ControllerInput.B == selected.get_input()):
                    selected = None
