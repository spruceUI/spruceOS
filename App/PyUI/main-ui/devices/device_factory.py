"""Create PyUI devices without importing the launcher or its menus."""

from devices.device import Device
from devices.miyoo.mini.miyoo_mini_flip_specific_model_variables import MIYOO_MINI_FLIP_VARIABLES, MIYOO_MINI_PLUS, MIYOO_MINI_V1_V2_V3_VARIABLES, MIYOO_MINI_V4_VARIABLES


def initialize_device(device, main_ui_mode):
    if "MIYOO_FLIP" == device or "SPRUCE_MIYOO_FLIP" == device:
        from devices.miyoo.flip.miyoo_flip import MiyooFlip
        Device.init(MiyooFlip(device, main_ui_mode))
    elif "MIYOO_MINI" == device:
        from devices.miyoo.mini.miyoo_mini_common import MiyooMiniCommon
        Device.init(MiyooMiniCommon(device,main_ui_mode,MIYOO_MINI_V1_V2_V3_VARIABLES))
    elif "MIYOO_MINI_V4" == device:
        from devices.miyoo.mini.miyoo_mini_common import MiyooMiniCommon
        Device.init(MiyooMiniCommon(device,main_ui_mode,MIYOO_MINI_V4_VARIABLES))
    elif "MIYOO_MINI_PLUS" == device:
        from devices.miyoo.mini.miyoo_mini_common import MiyooMiniCommon
        Device.init(MiyooMiniCommon(device,main_ui_mode,MIYOO_MINI_PLUS))
    elif "MIYOO_MINI_FLIP" == device:
        from devices.miyoo.mini.miyoo_mini_common import MiyooMiniCommon
        Device.init(MiyooMiniCommon(device,main_ui_mode,MIYOO_MINI_FLIP_VARIABLES))
    elif "SPRIG_MIYOO_MINI" == device:
        from devices.miyoo.mini.sprig_miyoo_mini_common import SprigMiyooMiniCommon
        Device.init(SprigMiyooMiniCommon(device, main_ui_mode,MIYOO_MINI_V1_V2_V3_VARIABLES))
    elif "SPRIG_MIYOO_MINI_V4" == device:
        from devices.miyoo.mini.sprig_miyoo_mini_common import SprigMiyooMiniCommon
        Device.init(SprigMiyooMiniCommon(device, main_ui_mode,MIYOO_MINI_V4_VARIABLES))
    elif "SPRIG_MIYOO_MINI_PLUS" == device:
        from devices.miyoo.mini.sprig_miyoo_mini_common import SprigMiyooMiniCommon
        Device.init(SprigMiyooMiniCommon(device, main_ui_mode,MIYOO_MINI_PLUS))
    elif "SPRIG_MIYOO_MINI_FLIP" == device:
        from devices.miyoo.mini.sprig_miyoo_mini_common import SprigMiyooMiniCommon
        Device.init(SprigMiyooMiniCommon(device, main_ui_mode,MIYOO_MINI_FLIP_VARIABLES))
    elif "TRIMUI_BRICK" == device or "SPRUCE_TRIMUI_BRICK" == device:
        from devices.trimui.trim_ui_brick import TrimUIBrick
        Device.init(TrimUIBrick(device,main_ui_mode))
    elif "TRIMUI_BRICK_PRO" == device or "SPRUCE_TRIMUI_BRICK_PRO" == device:
        from devices.trimui.trim_ui_brick_pro import TrimUIBrickPro
        Device.init(TrimUIBrickPro(device,main_ui_mode))
    elif "TRIMUI_SMART_PRO" == device or "SPRUCE_TRIMUI_SMART_PRO" == device:
        from devices.trimui.trim_ui_smart_pro import TrimUISmartPro
        Device.init(TrimUISmartPro(device,main_ui_mode))
    elif "TRIMUI_SMART_PRO_S" == device or "SPRUCE_TRIMUI_SMART_PRO_S" == device:
        from devices.trimui.trim_ui_smart_pro_s import TrimUISmartProS
        Device.init(TrimUISmartProS(device,main_ui_mode))
    elif "MIYOO_A30" == device or "SPRUCE_MIYOO_A30" == device:
        from devices.miyoo.a30.miyoo_a30 import MiyooA30
        Device.init(MiyooA30(device, main_ui_mode))
    elif "ANBERNIC_RGXX720480" == device:
        from devices.anbernic.anbernic_xx_720_x_480 import Anbernic720x480
        Device.init(Anbernic720x480(main_ui_mode))
    elif "ANBERNIC_RG28XX" == device:
        from devices.anbernic.anbernic_rg28xx import AnbernicRG28xx
        Device.init(AnbernicRG28xx(main_ui_mode))
    elif "MINILOONG_POCKET1" == device:
        from devices.darkmoss.miniloong_pocket1 import MiniloongPocket1
        Device.init(MiniloongPocket1(device, main_ui_mode))
    elif "ANBERNIC_RGCUBEXX" == device:
        from devices.anbernic.anbernic_rgcubexx import AnbernicRGCubeXX
        Device.init(AnbernicRGCubeXX(main_ui_mode))
    elif "ANBERNIC_RGXX640480" == device:
        from devices.anbernic.anbernic_xx_640_x_480 import Anbernic640x480
        Device.init(Anbernic640x480(main_ui_mode))
    elif "ANBERNIC_MUOS" == device:
        from devices.muos.muos_anbernic_rgxx import MuosAnbernicRGXX
        Device.init(MuosAnbernicRGXX(device))
    elif "ROCKNIX_RGDS" == device:
        from devices.rocknix.rocknix_rgds import RocknixRgds
        Device.init(RocknixRgds(device))
    elif "RG353M" == device:
        from devices.darkmoss.rg353m import Rg353m
        Device.init(Rg353m(device))
    elif "RGB30" == device:
        from devices.darkmoss.rgb30 import Rgb30
        Device.init(Rgb30(device))
    elif "RGB20SX" == device:
        from devices.darkmoss.rgb20sx import Rgb20sx
        Device.init(Rgb20sx(device))
    elif "A10MINI" == device:
        from devices.darkmoss.a10mini import A10Mini
        Device.init(A10Mini(device))
    elif "A10MINIV4" == device:
        from devices.darkmoss.a10miniv4 import A10MiniV4
        Device.init(A10MiniV4(device))
    elif "MAGICX_XU_MINI_M" == device:
        from devices.darkmoss.xumini import XuMiniM
        Device.init(XuMiniM(device))
    elif "G350" == device:
        from devices.darkmoss.g350 import G350
        Device.init(G350(device))
    elif "POWKIDDY_V10" == device:
        from devices.darkmoss.v10 import V10
        Device.init(V10(device))
    elif "GKD_PIXEL2" == device:
        from devices.gkd.gkd_pixel2 import GKDPixel2
        Device.init(GKDPixel2(device, main_ui_mode))
    elif "SPRUCE" == device:
        from devices.env.spruce.spruce_device import SpruceDevice
        Device.init(SpruceDevice(main_ui_mode))
    elif "DESKTOP" == device:
        # A window on a Mac or PC, for development: see App/PyUI/docs/desktop_readme.txt
        from devices.desktop.desktop_device import DesktopDevice
        Device.init(DesktopDevice(main_ui_mode))
    else:
        raise RuntimeError(f"{device} is not a supported device")
