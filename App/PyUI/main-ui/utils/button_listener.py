

from devices.device import Device


class ButtonListener:
    def __init__(self):
        pass

    def start(self):
        controller_interface = Device.get_device().get_controller_interface()
        controller_interface.print_key_state_changes()
        while(True):
            controller_interface.get_input(1000)
