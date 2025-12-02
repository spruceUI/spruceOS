
import json
import subprocess
from devices.charge.charge_status import ChargeStatus
from utils import throttle


class AxpTestMehthods():
        
    @throttle.limit_refresh(5)
    @staticmethod
    def get_charge_status():
        try:
            # Run axp_test and parse JSON
            result = subprocess.run(
                ["/customer/app/axp_test"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=2
            )
            data = json.loads(result.stdout.strip())
            charging = int(data.get("charging", 0))
                
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
            # Run axp_test and capture its JSON output
            result = subprocess.run(
                ["/customer/app/axp_test"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=2
            )
            data = json.loads(result.stdout.strip())
            return data.get("battery", 0)
        except Exception:
            return 0