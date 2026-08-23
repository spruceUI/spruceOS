from devices.anbernic.anbernic_xx_common import AnbernicXXCommon
import os


class Anbernic640x480(AnbernicXXCommon):
    def __init__(self, main_ui_mode):
        self.device_name = "ANBERNIC_RGXX640480"
        super().__init__(main_ui_mode)
    
    def screen_width(self):
        return 640
    
    def screen_height(self):
        return 480
        
    def screen_rotation(self):
        return 0
