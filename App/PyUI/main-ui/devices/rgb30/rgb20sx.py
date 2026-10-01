from devices.rgb30.rgb30 import Rgb30


class Rgb20sx(Rgb30):
    """Powkiddy RGB20SX: the RGB30 board with an RTL8723DS radio and a 5000mAh
    battery, booting the RGB30 image."""

    SYSTEM_JSON = "/mnt/SDCARD/App/PyUI/config/rgb20sx-system.json"
    SYSTEM_JSON_DEFAULT = "rgb20sx-system.json"
