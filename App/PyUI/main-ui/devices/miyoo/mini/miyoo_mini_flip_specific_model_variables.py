

from devices.charge.charge_status import ChargeStatus
from devices.miyoo.mini.axp_test_methods import AxpTestMehthods
from devices.miyoo.mini.og_mini_methods import OgMiniMethods


class MiyooMiniSpecificModelVariables():

    def __init__(self, width, height, supports_wifi, poweroff_cmd, reboot_cmd, get_charge_status, get_battery_percent):
        self.width = width
        self.height = height
        self.supports_wifi = supports_wifi
        self.poweroff_cmd = poweroff_cmd
        self.reboot_cmd = reboot_cmd
        self.get_charge_status = get_charge_status
        self.get_battery_percent = get_battery_percent

# --- Constant model presets ---

        
MIYOO_MINI_V1_V2_V3_VARIABLES = MiyooMiniSpecificModelVariables(
    width=640,
    height=480,
    supports_wifi=False,
    poweroff_cmd="reboot",
    reboot_cmd=None,
    get_charge_status=OgMiniMethods.get_charge_status,
    get_battery_percent=OgMiniMethods.get_battery_percent
)

MIYOO_MINI_V4_VARIABLES = MiyooMiniSpecificModelVariables(
    width=752,
    height=560,
    supports_wifi=False,
    poweroff_cmd="reboot",
    reboot_cmd=None,
    get_charge_status=OgMiniMethods.get_charge_status,
    get_battery_percent=OgMiniMethods.get_battery_percent
)

MIYOO_MINI_PLUS = MiyooMiniSpecificModelVariables(
    width=640,
    height=480,
    supports_wifi=True,
    poweroff_cmd="poweroff",
    reboot_cmd="reboot",
    get_charge_status=AxpTestMehthods.get_charge_status,
    get_battery_percent=AxpTestMehthods.get_battery_percent
)

MIYOO_MINI_FLIP_VARIABLES = MiyooMiniSpecificModelVariables(
    width=752,
    height=560,
    supports_wifi=True,
    poweroff_cmd="poweroff",
    reboot_cmd="reboot",
    get_charge_status=AxpTestMehthods.get_charge_status,
    get_battery_percent=AxpTestMehthods.get_battery_percent
)
