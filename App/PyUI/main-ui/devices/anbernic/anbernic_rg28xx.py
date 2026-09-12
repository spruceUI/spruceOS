from devices.anbernic.anbernic_xx_common import AnbernicXXCommon
import os
import subprocess
from utils.logger import PyUiLogger


class AnbernicRG28xx(AnbernicXXCommon):
    """The XX line's portrait-panel model, and the one whose radio is USB.

    The shell side owns the radio verdict. Two markers, set by
    device_wifi_power_on in AnbernicXXCommon.sh: /tmp/wifi_unavailable when
    the 8188eu module refused to load (sticky for the session) and
    /tmp/wifi_radio_absent when no adapter was on the USB bus (cleared the
    moment one is seen). supports_wifi keys on both, re-checking the bus
    itself when the absent marker is set, so an adapter plugged in after boot
    brings the WiFi entry back without a reboot. enable_wifi hands the whole
    bring-up to the shell's enable_wifi, which is the only path that loads
    the USB driver; the XX-common version starts wpa_supplicant on a wlan0
    that may not exist yet.
    """

    WIFI_UNAVAILABLE_FLAG = "/tmp/wifi_unavailable"
    WIFI_RADIO_ABSENT_FLAG = "/tmp/wifi_radio_absent"
    USB_SYS = "/sys/bus/usb/devices"
    # The ids the payload 8188eu.ko binds (modinfo -F alias); the cfg's
    # WIFI_USB_IDS wins when it is in the environment spruce launched us with.
    USB_IDS = ("0bda:8179", "0bda:0179", "0bda:f179", "2357:010c", "2357:0111",
               "07b8:8179", "2001:330f", "2001:3310", "2001:3311", "2001:331b",
               "0b05:18f0", "7392:b811", "0df6:0076", "056e:4008", "2c4e:0102")
    SPRUCE_HELPER_FUNCTIONS = "/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

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

    def enable_wifi(self):
        # Record the preference the way the XX-common path does, then let the
        # shell do the bring-up: bus check, module load, wlan0, supplicant,
        # DHCP client, network services - and the radio-less refusal with its
        # reason in spruce.log. Not blocking the UI on the enumeration wait is
        # why this is a Popen and not a run.
        self.system_config.set_wifi(1)
        self.system_config.save_config()
        if not os.path.exists(self.SPRUCE_HELPER_FUNCTIONS):
            PyUiLogger.get_logger().error(f"{self.SPRUCE_HELPER_FUNCTIONS} missing; cannot bring WiFi up")
            return
        try:
            subprocess.Popen(
                ["/bin/sh", "-c", f". {self.SPRUCE_HELPER_FUNCTIONS} && enable_wifi"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            PyUiLogger.get_logger().info("WiFi bring-up handed to the shell enable_wifi")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error starting wifi: {e}")
