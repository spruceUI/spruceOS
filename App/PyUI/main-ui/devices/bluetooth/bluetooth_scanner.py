import subprocess
import threading
import time
from dataclasses import dataclass

# Current import (per your note this will change later)
from devices.utils.process_runner import ProcessRunner
from utils.logger import PyUiLogger


@dataclass
class BluetoothDevice:
    address: str
    name: str
    paired: bool = False 

    def __init__(self, address: str, name: str, paired: bool):
        self.address = address
        self.name = name
        self.paired = paired

class BluetoothScanner:
    SCAN_INTERVAL = 2.0

    def __init__(self):
        self.log = PyUiLogger.get_logger()

        self._devices = {}
        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._thread = None

        self._scan_proc = None

    # ----------------------------
    # Public API
    # ----------------------------

    def start(self):
        self.log.info("BluetoothScanner.start() called")

        if self._thread and self._thread.is_alive():
            self.log.info("BluetoothScanner: scanner thread already running")
            return

        self._stop_event.clear()

        self._ensure_bluetooth_services()

        self._thread = threading.Thread(
            target=self._scanner_thread,
            name="BluetoothScannerThread",
            daemon=True
        )
        self._thread.start()

    def stop(self):
        self.log.info("BluetoothScanner.stop() called")

        self._stop_event.set()

        if self._scan_proc:
            try:
                self.log.info("BluetoothScanner: stopping scan process")
                self._scan_proc.terminate()
            except Exception as e:
                self.log.info(f"BluetoothScanner: failed stopping scan process: {e}")
            self._scan_proc = None

        # Best effort scan off
        self._run_cmd(["bluetoothctl", "scan", "off"])

        if self._thread:
            self._thread.join(timeout=2.0)
            self._thread = None

        self.log.info("BluetoothScanner stopped")

    def scan_devices(self):
        """Returns list of uniquely seen devices."""
        with self._lock:
            return list(self._devices.values())

    # ----------------------------
    # Internal
    # ----------------------------

    def _ensure_bluetooth_services(self):
        self.log.info("Ensuring bluetooth services are running...")

        try:
            subprocess.Popen(
                ["/usr/libexec/bluetooth/bluetoothd", "-f", "/etc/bluetooth/main.conf"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            self.log.info("bluetoothd started (or already running)")
        except Exception as e:
            self.log.info(f"Failed starting bluetoothd: {e}")

        try:
            subprocess.Popen(
                ["bluealsa", "-p", "a2dp-source"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            self.log.info("bluealsa started (or already running)")
        except Exception as e:
            self.log.info(f"Failed starting bluealsa: {e}")

        # Give dbus a moment
        time.sleep(1.0)

    def _scanner_thread(self):
        self.log.info("BluetoothScanner: scanner thread entering")

        # Power on bluetooth (blocking is safe)
        self._run_cmd(["bluetoothctl", "power", "on"])

        # Start scan NON-BLOCKING (important)
        try:
            self.log.info("BluetoothScanner: starting bluetoothctl scan on (non-blocking)")
            self._scan_proc = subprocess.Popen(
                ["bluetoothctl", "scan", "on"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
        except Exception as e:
            self.log.info(f"BluetoothScanner: failed starting scan: {e}")

        self.log.info("BluetoothScanner: bluetooth power on + scan enabled")

        # Poll loop
        while not self._stop_event.is_set():
            try:
                self._poll_devices()
            except Exception as e:
                self.log.info(f"BluetoothScanner: poll failed: {e}")

            time.sleep(self.SCAN_INTERVAL)

        self.log.info("BluetoothScanner: scanner thread exiting")

    def _poll_devices(self):
        """Runs `bluetoothctl devices` and parses output."""
        #self.log.info("BluetoothScanner: polling devices")

        output = self._run_cmd(["bluetoothctl", "devices"], log_stdout=False)
        if not output:
            return

        for line in output.splitlines():
            PyUiLogger.get_logger().debug(f"BluetoothScanner: scan line: {line}")
            line = line.strip()
            if not line.startswith("Device") and not line.startswith("Controller"):
                continue

            # Format:
            # Device AA:BB:CC:DD:EE:FF Device Name
            parts = line.split(" ", 2)
            if len(parts) < 3:
                continue

            _, mac, name = parts

            with self._lock:
                if mac not in self._devices:
                    paired = self._check_paired(mac)
                    self.log.info(f"BluetoothScanner: discovered {mac} ({name})")
                    self._devices[mac] = BluetoothDevice(mac, name, paired)

    def _check_paired(self, mac: str) -> bool:
        """Checks if a device is paired using `bluetoothctl info`."""
        output = self._run_cmd(["bluetoothctl", "info", mac])
        if not output:
            return False
        return "Paired: yes" in output
    
    def refresh_devices(self):
        """Clears the device list to force re-scan."""
        with self._lock:
            self._devices.clear()
    
    def _run_cmd(self, cmd, log_stdout=True):
        return ProcessRunner.run_cmd("BluetoothScanner", cmd, log_stdout=log_stdout)