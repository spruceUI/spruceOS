from devices.anbernic.anbernic_xx_common import AnbernicXXCommon
import os


#ln -s sdcard SDCARD
#/mnt/vendor/ctrl/loadapp.sh
#/mnt/vendor/ctrl/dmenu_ln
#scp loadapp.sh root@10.0.0.156:/mnt/vendor/ctrl/loadapp.sh
class AnbernicRG28xx(AnbernicXXCommon):
    def __init__(self):
        # For now
        self.device_name = "MIYOO_A30"
        super().__init__()
                   
    def _set_lumination_to_config(self):
        import fcntl
        import struct
        DEV = "/dev/disp"
        IOCTL_SET_BRIGHTNESS = 0x102
        #Is actually 128
        val = self.map_backlight_from_10_to_full_255(self.system_config.backlight //2)

        # 4 unsigned long values (ARM64 = 8 bytes each)
        args = struct.pack("QQQQ", 0, val, 0, 0)

        fd = os.open(DEV, os.O_RDWR)
        try:
            fcntl.ioctl(fd, IOCTL_SET_BRIGHTNESS, args)
        finally:
            os.close(fd)     
    
    def screen_width(self):
        return 640
    
    def screen_height(self):
        return 480
        
    def screen_rotation(self):
        return 270
