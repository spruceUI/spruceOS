from devices.anbernic.anbernic_xx_common import AnbernicXXCommon


class Anbernic720x480(AnbernicXXCommon):
    def __init__(self, main_ui_mode):
        self.device_name = "ANBERNIC_RGXX720480"
        super().__init__(main_ui_mode)
                       
    def screen_width(self):
        return 720
    
    def screen_height(self):
        return 480
        
    def screen_rotation(self):
        return 0

    def _set_lumination_to_config(self):
        import fcntl
        import os
        import struct

        val = max(1, self.map_backlight_from_10_to_full_255(self.system_config.backlight) // 2)
        args = struct.pack("QQQQ", 0, val, 0, 0)

        fd = os.open("/dev/disp", os.O_RDWR)
        try:
            fcntl.ioctl(fd, 0x102, args)
        finally:
            os.close(fd)
