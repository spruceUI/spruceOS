
import json
import subprocess
from devices.charge.charge_status import ChargeStatus
from utils import throttle


class OgMiniMethods():
    
    @throttle.limit_refresh(5)
    @staticmethod
    def get_charge_status():
        try:
            # Read GPIO 59 value
            with open("/sys/devices/gpiochip0/gpio/gpio59/value", "r") as f:
                value = f.read().strip()

            charging = int(value)
                    
            if charging == 0:
                return ChargeStatus.DISCONNECTED
            else:
                return ChargeStatus.CHARGING
        except Exception:
            return ChargeStatus.DISCONNECTED


    @throttle.limit_refresh(15)
    @staticmethod
    def get_battery_percent():
        try:
            result = subprocess.run(
                ["read_battery"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=2
            )
            value = int(result.stdout.strip())
            return value
        except Exception:
            return 0