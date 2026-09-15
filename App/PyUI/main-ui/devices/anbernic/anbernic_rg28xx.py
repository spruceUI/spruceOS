from devices.anbernic.anbernic_xx_common import AnbernicXXCommon
import os


class AnbernicRG28xx(AnbernicXXCommon):
    USB_SYS = "/sys/bus/usb/devices"
    # The ids the payload 8188eu.ko binds (modinfo -F alias); the cfg's
    # WIFI_USB_IDS wins when it is in the environment spruce launched us with.
    USB_IDS = ("0bda:8179", "0bda:0179", "0bda:f179", "2357:010c", "2357:0111",
               "07b8:8179", "2001:330f", "2001:3310", "2001:3311", "2001:331b",
               "0b05:18f0", "7392:b811", "0df6:0076", "056e:4008", "2c4e:0102")

    def __init__(self, main_ui_mode):
        # For now
        self.device_name = "ANBERNIC_RG28XX"
        super().__init__(main_ui_mode)
    
    def screen_width(self):
        return 640
    
    def screen_height(self):
        return 480
        
    def screen_rotation(self):
        return 0

    def _usb_radio_ids(self):
        env = os.environ.get("WIFI_USB_IDS", "").split()
        return tuple(i.lower() for i in env) if env else self.USB_IDS

    def _usb_radio_present(self):
        """Same sysfs read as the shell's wifi_usb_radio_present."""
        ids = self._usb_radio_ids()
        try:
            for dev in os.listdir(self.USB_SYS):
                base = os.path.join(self.USB_SYS, dev)
                try:
                    with open(os.path.join(base, "idVendor")) as f:
                        vendor = f.read().strip().lower()
                    with open(os.path.join(base, "idProduct")) as f:
                        product = f.read().strip().lower()
                except OSError:
                    continue
                if f"{vendor}:{product}" in ids:
                    return True
        except OSError:
            pass
        return False

    def supports_wifi(self):
        return self._usb_radio_present()
