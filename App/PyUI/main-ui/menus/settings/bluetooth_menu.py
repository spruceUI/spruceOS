
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.bluetooth.bluetooth_scanner import BluetoothScanner
from devices.device import Device
from devices.wifi.wifi_scanner import WiFiNetwork, WiFiScanner
from display.display import Display
from display.font_purpose import FontPurpose
from display.on_screen_keyboard import OnScreenKeyboard
from display.render_mode import RenderMode
from themes.theme import Theme
from views.descriptive_list_view import DescriptiveListView
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class BluetoothMenu:
    def __init__(self, display : Display, controller: Controller, device: Device, theme: Theme):
        self.display : Display = display
        self.controller : Controller = controller
        self.device : Device= device
        self.theme : Theme= theme
        self.bluetooth_scanner = BluetoothScanner()
        self.on_screen_keyboard = OnScreenKeyboard(display,controller,device,theme)
        self.view_creator = ViewCreator(display,controller,device,theme)

    def bluetooth_adjust(self):
        if self.device.is_bluetooth_enabled:
            self.device.disable_bluetooth()
        else:
            self.device.enable_bluetooth()

    def toggle_pairing_device(self, device):
        self.bluetooth_scanner.connect_to_device(device.address)

    def scan_for_devices(self):
        self.display.clear("Bluetooth")
        self.display.render_text(
            text = "Scanning for Bluetooth Devices (~10s)",
            x = self.device.screen_width // 2,
            y = self.display.get_usable_screen_height() // 2,
            color = self.theme.text_color(FontPurpose.DESCRIPTIVE_LIST_TITLE),
            purpose = FontPurpose.DESCRIPTIVE_LIST_TITLE,
            render_mode=RenderMode.MIDDLE_CENTER_ALIGNED
        )
        self.display.present()
        return self.bluetooth_scanner.scan_devices()


    def show_bluetooth_menu(self):
        bluetooth_enabled = self.device.is_bluetooth_enabled()
        selected = Selection(None, None, 0)
        first_loop = True
        devices = []
        while(selected is not None):
            option_list = []
            option_list.append(
                GridOrListEntry(
                        primary_text="Status",
                        value_text="<    " + ("On" if bluetooth_enabled else "Off") + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.bluetooth_adjust
                    )
            )
            

            if(bluetooth_enabled):
                if(first_loop):
                    first_loop = False
                    devices = self.scan_for_devices()

                for device in devices:
                    option_list.append(
                        GridOrListEntry(
                                primary_text=device.name,
                                value_text=device.address,
                                image_path=None,
                                image_path_selected=None,
                                description=None,
                                icon=None,
                                value=lambda device=device: self.toggle_pairing_device(device)  
                            )
                    )

            list_view = self.view_creator.create_view(
                    view_type=ViewType.DESCRIPTIVE_LIST_VIEW,
                    top_bar_text="WiFi Configuration", 
                    options=option_list,
                    selected_index=selected.get_index())

            selected = list_view.get_selection([ControllerInput.A,ControllerInput.X, ControllerInput.DPAD_LEFT, ControllerInput.DPAD_RIGHT,
                                                ControllerInput.L1, ControllerInput.R1])

            if(selected is not None):
                if(ControllerInput.X == selected.get_input()):
                    devices = self.scan_for_devices()
                else:
                    selected.get_selection().value()

