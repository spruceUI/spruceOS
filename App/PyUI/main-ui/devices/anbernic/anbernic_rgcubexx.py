from devices.anbernic.anbernic_xx_common import AnbernicXXCommon
import os


class AnbernicRGCubeXX(AnbernicXXCommon):
    def __init__(self, main_ui_mode):
        # For now
        self.device_name = "ANBERNIC_RGCUBEXX"
        super().__init__(main_ui_mode)
                   
    def screen_width(self):
        return 720
    
    def screen_height(self):
        return 720
        
    def screen_rotation(self):
        return 0
