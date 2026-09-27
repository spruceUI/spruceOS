from devices.anbernic.anbernic_xx_common import AnbernicXXCommon


class AnbernicRG28xx(AnbernicXXCommon):
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

    def supports_wifi(self):
        # The radio is a USB dongle that may or may not be plugged in. The
        # shell decides whether one is present; PyUI only shows the answer.
        return self._wifi_status().get("radio", "1") == "1"
