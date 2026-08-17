from devices.abstract_device import AbstractDevice
from devices.miyoo.device_user_config import DeviceUserConfig
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

    @staticmethod
    def supports_device(devices):
        """Whether the running device matches a config "devices" list.

        An absent or empty list means "every device", which is how most
        entries are written. Otherwise the list is matched against every
        name the device answers to, not just its model name: a device may
        also report a family token shared by its whole hardware line, so
        one config entry can cover the line instead of naming each model.
        See get_device_names() on DeviceCommon.
        """
        if not devices:
            return True
        return any(name in devices for name in Device.get_device().get_device_names())
