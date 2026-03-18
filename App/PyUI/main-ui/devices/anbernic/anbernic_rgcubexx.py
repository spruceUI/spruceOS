from devices.anbernic.anbernic_xx_common import AnbernicXXCommon
import os


#ln -s sdcard SDCARD
#/mnt/vendor/ctrl/loadapp.sh
#/mnt/vendor/ctrl/dmenu_ln
#scp loadapp.sh root@10.0.0.156:/mnt/vendor/ctrl/loadapp.sh
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
