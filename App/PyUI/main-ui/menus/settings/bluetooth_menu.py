
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from devices.bluetooth.bluetooth_scanner import BluetoothScanner
from devices.utils.process_runner import ProcessRunner
from display.display import Display
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


from menus.language.language import Language

class BluetoothMenu:
    def __init__(self):
        self.bluetooth_scanner = BluetoothScanner()

    def bluetooth_adjust(self):
        if Device.get_device().is_bluetooth_enabled():
            Device.get_device().disable_bluetooth()
        else:
            Device.get_device().enable_bluetooth()

    def toggle_pairing_device(self, device):
        self.connect_device(device)
        Controller.new_bt_device_paired()


    def connect_device(self, device) -> bool:
        log = PyUiLogger.get_logger()
        log.info(f"connecting to ({device.address})")

        steps = [
            ("pair",    ["bluetoothctl", "pair", device.address],    "Pairing successful"),
            ("trust",   ["bluetoothctl", "trust", device.address],   "trust succeeded"),
            ("connect", ["bluetoothctl", "connect", device.address], "Connection successful"),
        ]

        for name, cmd, success_token in steps:
            log.info(f"Bluetooth connect step: {name}")

            output = ProcessRunner.run_cmd("BluetoothMenu", cmd)
            log.info(f"{name} output: {output}")

            if not output or success_token.lower() not in output.lower():
                log.info(f"{name} FAILED for {device.address}")
                Display.display_message(f"Bluetooth device {device.name} failed to connect at step: {name}. {output}", duration_ms=5000)
                return False

        Display.display_message(f"Bluetooth device {device.name} connected successfully", duration_ms=5000)
        self.bluetooth_scanner.refresh_devices()
        return True


    def show_bluetooth_menu(self):
        try:
            selected = Selection(None, None, 0)
            devices = []
            bluetooth_enabled = Device.get_device().is_bluetooth_enabled()
            if(not bluetooth_enabled):
                self.bluetooth_adjust()
            self.bluetooth_scanner.start()

            while(selected is not None):
                bluetooth_enabled = Device.get_device().is_bluetooth_enabled()
                option_list = []
                option_list.append(
                    GridOrListEntry(
                            primary_text=Language.status(),
                            value_text="<    " + ("Scanning" if bluetooth_enabled else "Off") + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.bluetooth_adjust
                        )
                )
                
                if(bluetooth_enabled):
                    devices = self.bluetooth_scanner.scan_devices()

                    for bt_device in devices:
                        option_list.append(
                            GridOrListEntry(
                                    primary_text="✓ " + bt_device.name if bt_device.paired else bt_device.name,
                                    value_text=bt_device.address,
                                    image_path=None,
                                    image_path_selected=None,
                                    description=None,
                                    icon=None,
                                    value=lambda device=bt_device: self.toggle_pairing_device(device)  
                                )
                        )

                list_view = ViewCreator.create_view(
                        view_type=ViewType.ICON_AND_DESC,
                        top_bar_text="Bluetooth Configuration", 
                        options=option_list,
                        selected_index=selected.get_index()) #always reset to the top in case devices change during a scan

                accepted_inputs = [ControllerInput.A, ControllerInput.DPAD_LEFT, ControllerInput.DPAD_RIGHT,
                                                    ControllerInput.L1, ControllerInput.R1, ControllerInput.X]
                selected = list_view.get_selection(accepted_inputs)

                if(selected.get_input() in accepted_inputs):
                    PyUiLogger.get_logger().info(f"bluetooth_enabled={bluetooth_enabled}")
                    if(ControllerInput.A == selected.get_input() 
                        or ControllerInput.DPAD_LEFT == selected.get_input() 
                        or ControllerInput.DPAD_RIGHT == selected.get_input()):
                        selected.get_selection().value()
                elif(ControllerInput.B == selected.get_input()):
                    selected = None

        finally:
            Display.display_message("Stopping Bluetooth scanner...")
            self.bluetooth_scanner.stop()
