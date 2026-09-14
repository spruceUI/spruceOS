from devices.anbernic.anbernic_xx_common import AnbernicXXCommon
import os


class AnbernicRG28xx(AnbernicXXCommon):
    """The XX line's portrait-panel model, and the one whose radio is USB.

    The shell side owns the radio verdict. Two markers, set by
    device_wifi_power_on in AnbernicXXCommon.sh: /tmp/wifi_unavailable when
    the 8188eu module refused to load (sticky for the session) and
    /tmp/wifi_radio_absent when no adapter was on the USB bus (cleared the
    moment one is seen). supports_wifi keys on both, re-checking the bus
    itself when the absent marker is set, so an adapter plugged in after boot
    brings the WiFi entry back without a reboot. WiFi on and off go through
    spruce's wifi.sh, whose enable_wifi is the only path that loads the USB driver.
    """

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
        if os.path.exists(self.WIFI_UNAVAILABLE_FLAG):
            return False
        if os.path.exists(self.WIFI_RADIO_ABSENT_FLAG):
            return self._usb_radio_present()
        return True
