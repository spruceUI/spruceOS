from devices.abstract_device import AbstractDevice
from devices.miyoo.system_config import SystemConfig
from menus.games.utils.rom_info import RomInfo
from utils.image_utils import ImageUtils


class Device:
    _impl: AbstractDevice = None

    @staticmethod
    def init(impl: AbstractDevice):
        Device._impl = impl

    @staticmethod
    def get_device():
        return Device._impl