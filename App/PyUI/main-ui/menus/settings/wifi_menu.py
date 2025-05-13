
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from devices.wifi.wifi_scanner import WiFiNetwork, WiFiScanner
from display.display import Display
from display.font_purpose import FontPurpose
from display.on_screen_keyboard import OnScreenKeyboard
from display.render_mode import RenderMode
from themes.theme import Theme
from utils.logger import PyUiLogger
from views.descriptive_list_view import DescriptiveListView
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class WifiMenu:
    def __init__(self, display : Display, controller: Controller, device: Device, theme: Theme):
        self.display : Display = display
        self.controller : Controller = controller
        self.device : Device= device
        self.theme : Theme= theme
        self.wifi_scanner = WiFiScanner()
        self.on_screen_keyboard = OnScreenKeyboard(display,controller,device,theme)
        self.view_creator = ViewCreator(display,controller,device,theme)

    def wifi_adjust(self):
        if self.device.is_wifi_enabled():
            self.device.disable_wifi()
        else:
            self.device.enable_wifi()

    def write_wpa_supplicant_conf(self,ssid, pw_line, file_path="/userdata/cfg/wpa_supplicant.conf"):
        # WPA configuration template
        config = f"""
ctrl_interface=/var/run/wpa_supplicant
update_config=1

network={{
    ssid="{ssid}"
    {pw_line}
}}
"""
        try:
            # Open the file in write mode and write the config
            with open(file_path, "w") as f:
                f.write(config.strip())
            PyUiLogger.get_logger().info(f"Configuration written to {file_path}")
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
            wifi_enabled = self.device.is_wifi_enabled()
            option_list = []
            option_list.append(
                GridOrListEntry(
                        primary_text="Status",
                        value_text="<    " + ("On" if wifi_enabled else "Off") + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.wifi_adjust
                    )
            )
            

            if(wifi_enabled):
                self.display.clear("WiFi")
                self.display.render_text(
                    text = "Scanning for Networks (~10s)",
                    x = self.device.screen_width // 2,
                    y = self.display.get_usable_screen_height() // 2,
                    color = self.theme.text_color(FontPurpose.DESCRIPTIVE_LIST_TITLE),
                    purpose = FontPurpose.DESCRIPTIVE_LIST_TITLE,
                    render_mode=RenderMode.MIDDLE_CENTER_ALIGNED)
                self.display.present()
                if(should_scan_for_wifi):
                    should_scan_for_wifi = False
                    networks = self.wifi_scanner.scan_networks(self.device)
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

            list_view = self.view_creator.create_view(
                    view_type=ViewType.DESCRIPTIVE_LIST_VIEW,
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
